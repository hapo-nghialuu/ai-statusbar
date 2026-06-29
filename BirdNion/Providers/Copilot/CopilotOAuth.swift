import Foundation

// MARK: - CopilotAccountStore

/// Quản lý nhiều tài khoản Copilot (GitHub OAuth) trên máy local.
/// Dữ liệu lưu tại ~/.config/birdnion/copilot-accounts.json (plain-text token).
public enum CopilotAccountStore {

    public struct Account: Codable, Equatable {
        public var label: String
        public var login: String?
        public var token: String

        public init(label: String, login: String? = nil, token: String) {
            self.label = label
            self.login = login
            self.token = token
        }
    }

    public struct Store: Codable {
        public var activeLabel: String?
        public var accounts: [Account]

        public init(activeLabel: String? = nil, accounts: [Account] = []) {
            self.activeLabel = activeLabel
            self.accounts = accounts
        }
    }

    // MARK: File location

    public static var fileURL: URL {
        let base = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".config/birdnion", isDirectory: true)
        return base.appendingPathComponent("copilot-accounts.json")
    }

    // MARK: Persistence

    /// Đọc store từ disk; trả về store rỗng nếu file chưa tồn tại.
    public static func load() -> Store {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let store = try? JSONDecoder().decode(Store.self, from: data)
        else {
            return Store()
        }
        return store
    }

    /// Lưu store xuống disk; tạo thư mục cha nếu cần.
    public static func save(_ store: Store) throws {
        let url = fileURL
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(store)
        try data.write(to: url, options: .atomic)
    }

    // MARK: Mutations (value-type helpers — caller owns the store)

    /// Thêm hoặc cập nhật account theo label. Nếu label đã tồn tại, token/login được cập nhật.
    public static func addAccount(
        to store: inout Store,
        label: String,
        token: String,
        login: String?
    ) {
        if let idx = store.accounts.firstIndex(where: { $0.label == label }) {
            store.accounts[idx].token = token
            store.accounts[idx].login = login
        } else {
            store.accounts.append(Account(label: label, login: login, token: token))
        }
    }

    /// Xoá account theo label. Nếu đang active → xoá activeLabel.
    public static func removeAccount(from store: inout Store, label: String) {
        store.accounts.removeAll { $0.label == label }
        if store.activeLabel == label {
            store.activeLabel = store.accounts.first?.label
        }
    }

    /// Đặt tài khoản active. Không làm gì nếu label không tồn tại.
    public static func setActive(in store: inout Store, label: String) {
        guard store.accounts.contains(where: { $0.label == label }) else { return }
        store.activeLabel = label
    }

    /// Trả về tài khoản đang active, hoặc account đầu tiên nếu activeLabel không hợp lệ.
    public static func activeAccount(in store: Store) -> Account? {
        if let label = store.activeLabel,
           let account = store.accounts.first(where: { $0.label == label }) {
            return account
        }
        return store.accounts.first
    }
}

// MARK: - CopilotDeviceFlowError

public enum CopilotDeviceFlowError: LocalizedError {
    case urlInvalid
    case httpError(Int)
    case timeout
    case denied
    case unexpectedResponse

    public var errorDescription: String? {
        switch self {
        case .urlInvalid:
            return "URL yêu cầu không hợp lệ."
        case .httpError(let code):
            return "Máy chủ trả về lỗi HTTP \(code)."
        case .timeout:
            return "Hết thời gian chờ xác thực. Vui lòng thử lại."
        case .denied:
            return "Yêu cầu đăng nhập bị từ chối."
        case .unexpectedResponse:
            return "Phản hồi từ máy chủ không đúng định dạng."
        }
    }
}

// MARK: - CopilotDeviceFlow

/// GitHub OAuth Device Flow cho Copilot (VS Code client_id).
/// Hỗ trợ cả github.com lẫn GitHub Enterprise.
public enum CopilotDeviceFlow {

    private static let clientID = "Iv1.b507a08c87ecfe98" // VS Code public Client ID
    private static let scope    = "read:user"

    // MARK: Public types

    public struct DeviceCode {
        public let userCode: String
        public let verificationURI: String
        public let deviceCode: String
        public let interval: Int
        public let expiresIn: Int
    }

    // MARK: Step 1 — request device code

    /// Khởi động Device Flow: trả về DeviceCode để hiển thị userCode cho người dùng.
    /// - Parameter host: hostname (mặc định "github.com"). Enterprise: "github.mycompany.com".
    public static func start(host: String = "github.com") async throws -> DeviceCode {
        guard let url = URL(string: "https://\(host)/login/device/code") else {
            throw CopilotDeviceFlowError.urlInvalid
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody(["client_id": clientID, "scope": scope])

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CopilotDeviceFlowError.httpError(http.statusCode)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let deviceCode   = json["device_code"]      as? String,
              let userCode     = json["user_code"]        as? String,
              let verifyURI    = json["verification_uri"] as? String,
              let expiresIn    = json["expires_in"]       as? Int,
              let interval     = json["interval"]         as? Int
        else {
            throw CopilotDeviceFlowError.unexpectedResponse
        }

        return DeviceCode(
            userCode: userCode,
            verificationURI: verifyURI,
            deviceCode: deviceCode,
            interval: interval,
            expiresIn: expiresIn
        )
    }

    // MARK: Step 2 — poll for token

    /// Poll cho đến khi người dùng xác nhận hoặc hết hạn.
    /// Trả về (token, login?) khi thành công. login có thể nil nếu /user API thất bại.
    public static func poll(
        host: String = "github.com",
        deviceCode: String,
        interval: Int
    ) async throws -> (token: String, login: String?) {
        guard let url = URL(string: "https://\(host)/login/oauth/access_token") else {
            throw CopilotDeviceFlowError.urlInvalid
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            "client_id":   clientID,
            "device_code": deviceCode,
            "grant_type":  "urn:ietf:params:oauth:grant-type:device_code",
        ])

        var currentInterval = interval

        while true {
            try await Task.sleep(nanoseconds: UInt64(currentInterval) * 1_000_000_000)
            try Task.checkCancellation()

            let (data, response) = try await URLSession.shared.data(for: request)

            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw CopilotDeviceFlowError.httpError(http.statusCode)
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CopilotDeviceFlowError.unexpectedResponse
            }

            if let error = json["error"] as? String {
                switch error {
                case "authorization_pending":
                    continue
                case "slow_down":
                    // GitHub yêu cầu tăng interval thêm 5 giây
                    currentInterval += 5
                    continue
                case "expired_token":
                    throw CopilotDeviceFlowError.timeout
                case "access_denied":
                    throw CopilotDeviceFlowError.denied
                default:
                    throw CopilotDeviceFlowError.unexpectedResponse
                }
            }

            guard let token = json["access_token"] as? String else {
                throw CopilotDeviceFlowError.unexpectedResponse
            }

            // Lấy login từ GitHub API (best-effort, không throw nếu thất bại)
            let login = await fetchLogin(host: host, token: token)
            return (token: token, login: login)
        }
    }

    // MARK: Helpers

    /// Lấy username từ /user API. Trả về nil nếu thất bại (không blocking).
    private static func fetchLogin(host: String, token: String) async -> String? {
        // github.com → api.github.com; enterprise → api.<host>
        let apiHost = (host == "github.com") ? "api.github.com" : "api.\(host)"
        guard let url = URL(string: "https://\(apiHost)/user") else { return nil }

        var request = URLRequest(url: url)
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let login = json["login"] as? String
        else {
            return nil
        }
        return login
    }

    private static func formBody(_ params: [String: String]) -> Data {
        let pairs = params.map { k, v in
            "\(percentEncode(k))=\(percentEncode(v))"
        }.joined(separator: "&")
        return Data(pairs.utf8)
    }

    private static func percentEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
