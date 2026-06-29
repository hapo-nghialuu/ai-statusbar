import Foundation

/// Kiro (AWS) quota provider.
///
/// Resolves the `kiro` or `kiro-cli` binary from PATH (mirrors ClaudeCLIVersionDetector pattern).
/// Subcommands:
///   - `kiro-cli whoami` — verifies login; parses email + auth method.
///   - `kiro-cli chat --no-interactive /usage` — usage output with credits %, plan, reset date.
/// ANSI codes are stripped before parsing.
/// Hard timeout of 25s total (20s for usage cmd + 5s for whoami); process group killed on timeout.
final class KiroProvider: QuotaProvider {
    let id = "kiro"
    let displayName = "Kiro"

    private let binaryResolver: () -> String?
    private let timeout: TimeInterval

    init(timeout: TimeInterval = 25) {
        self.timeout = timeout
        self.binaryResolver = { KiroProvider.resolveBinary() }
    }

    /// Testable init — inject a custom binary resolver.
    init(binaryResolver: @escaping () -> String?, timeout: TimeInterval = 25) {
        self.binaryResolver = binaryResolver
        self.timeout = timeout
    }

    func fetch() async throws -> ProviderStatus {
        do {
            return try await fetchInternal()
        } catch let err as KiroProviderError {
            return failure(err.localizedMessage)
        } catch {
            return failure(error.localizedDescription)
        }
    }

    // MARK: - Testing hook

    /// Parse raw CLI text (post ANSI-strip) into ProviderStatus (for unit tests).
    static func _parseForTesting(usageOutput: String, whoamiOutput: String?) -> ProviderStatus {
        let email = whoamiOutput.flatMap { parseWhoamiEmail(from: Self.stripANSI($0)) }
        do {
            let snapshot = try parseUsage(stripped: Self.stripANSI(usageOutput), accountEmail: email)
            return snapshot
        } catch {
            return ProviderStatus(id: "kiro", displayName: "Kiro", windows: [], lastUpdated: Date(), error: error.localizedDescription)
        }
    }

    // MARK: - Core fetch

    private func fetchInternal() async throws -> ProviderStatus {
        guard let binary = binaryResolver() else {
            throw KiroProviderError.binaryNotFound
        }

        // Run whoami (3s timeout, non-fatal on failure)
        let whoamiOut = try? runCommand(binary: binary, arguments: ["whoami"], timeout: 3)
        let email: String?
        if let out = whoamiOut {
            let stripped = Self.stripANSI(out)
            // Check for "not logged in" in whoami output
            let lower = stripped.lowercased()
            if lower.contains("not logged in") || lower.contains("login required") {
                throw KiroProviderError.notLoggedIn
            }
            email = Self.parseWhoamiEmail(from: stripped)
        } else {
            email = nil
        }

        // Run usage command (20s timeout with idle detection)
        let usageOut = try runCommand(binary: binary, arguments: ["chat", "--no-interactive", "/usage"], timeout: 20)
        let strippedUsage = Self.stripANSI(usageOut)

        let lowerUsage = strippedUsage.lowercased()
        if lowerUsage.contains("not logged in")
            || lowerUsage.contains("login required")
            || lowerUsage.contains("failed to initialize auth portal")
            || lowerUsage.contains("kiro-cli login")
            || lowerUsage.contains("oauth error")
        {
            throw KiroProviderError.notLoggedIn
        }

        return try Self.parseUsage(stripped: strippedUsage, accountEmail: email)
    }

    // MARK: - CLI execution

    /// Runs a kiro-cli subcommand synchronously via Foundation Process, bridged into async context.
    /// Hard kills the process + process group on timeout.
    private func runCommand(binary: String, arguments: [String], timeout: TimeInterval) throws -> String {
        let outPipe = Pipe()
        let errPipe = Pipe()

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binary)
        proc.arguments = arguments
        // Pass TERM so interactive prompts don't stall
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        proc.environment = env
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        proc.standardInput = FileHandle.nullDevice

        let sem = DispatchSemaphore(value: 0)
        proc.terminationHandler = { _ in sem.signal() }

        do {
            try proc.run()
        } catch {
            throw KiroProviderError.cliFailed("Không khởi động được kiro-cli: \(error.localizedDescription)")
        }

        // Move to a process group so we can kill all descendants
        let pid = proc.processIdentifier
        let pgid: pid_t? = (setpgid(pid, pid) == 0) ? pid : nil

        let didExit = sem.wait(timeout: .now() + timeout) == .success
        if !didExit {
            terminateGroup(pgid: pgid, proc: proc)
            throw KiroProviderError.timeout
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: outData, encoding: .utf8) ?? ""
        let stderr = String(data: errData, encoding: .utf8) ?? ""

        // Prefer stdout; fall back to stderr
        let combined = stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? stderr : stdout
        if proc.terminationStatus != 0, combined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw KiroProviderError.cliFailed("kiro-cli thoát với code \(proc.terminationStatus)")
        }
        return combined
    }

    private func terminateGroup(pgid: pid_t?, proc: Process) {
        if let g = pgid {
            killpg(g, SIGTERM)
        } else {
            proc.terminate()
        }
        Thread.sleep(forTimeInterval: 0.2)
        if proc.isRunning {
            if let g = pgid { killpg(g, SIGKILL) } else { proc.terminate() }
        }
    }

    // MARK: - Binary resolution

    /// Scans common PATH entries for `kiro` then `kiro-cli`.
    static func resolveBinary() -> String? {
        for name in ["kiro", "kiro-cli"] {
            if let path = which(name) { return path }
        }
        return nil
    }

    private static func which(_ name: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["which", name]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { return nil }
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let path = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    // MARK: - ANSI stripping

    /// Strips ANSI CSI and OSC escape sequences from CLI output.
    static func stripANSI(_ text: String) -> String {
        // Pattern covers CSI (ESC[ ... letter) and block/box drawing sequences
        guard let regex = try? NSRegularExpression(pattern: #"\x1B\[[0-9;?]*[A-Za-z]|\x1B\].*?\x07"#) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    // MARK: - Parsing

    /// Parses whoami output for email.
    private static func parseWhoamiEmail(from stripped: String) -> String? {
        for line in stripped.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.localizedCaseInsensitiveContains("email:") {
                let val = t.replacingOccurrences(of: #"(?i)^\s*email:\s*"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !val.isEmpty { return val }
            } else if t.contains("@"), !t.contains(" ") {
                return t
            }
        }
        return nil
    }

    /// Main parse from stripped usage output → ProviderStatus.
    /// Mirrors KiroStatusProbe parsing logic (regex-based).
    private static func parseUsage(stripped: String, accountEmail: String?) throws -> ProviderStatus {
        let trimmed = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw KiroProviderError.parseError("Output trống từ kiro-cli")
        }

        if trimmed.lowercased().contains("could not retrieve usage information") {
            throw KiroProviderError.parseError("kiro-cli không lấy được thông tin usage")
        }

        // -- Plan name --
        let planName = parsePlanName(from: stripped)

        // -- Reset date --
        let resetDate = parseResetDate(from: stripped)

        // -- Credits percentage from "████ X%" --
        var creditsPercent: Double = 0
        var matchedPercent = false
        if let percentMatch = stripped.range(of: #"█+\s*(\d+)%"#, options: .regularExpression) {
            let seg = String(stripped[percentMatch])
            if let numMatch = seg.range(of: #"\d+"#, options: .regularExpression) {
                creditsPercent = Double(String(seg[numMatch])) ?? 0
                matchedPercent = true
            }
        }

        // -- Credits used/total from "(X.XX of Y covered in plan)" --
        var creditsUsed: Double = 0
        var creditsTotal: Double = 50
        var matchedCredits = false
        if let creditsMatch = stripped.range(of: #"\((\d+\.?\d*)\s+of\s+(\d+)\s+covered"#, options: .regularExpression) {
            let seg = String(stripped[creditsMatch])
            let nums = extractNumbers(seg)
            if nums.count >= 2 {
                creditsUsed = nums[0]
                creditsTotal = nums[1]
                matchedCredits = true
            }
        }
        if !matchedPercent, matchedCredits, creditsTotal > 0 {
            creditsPercent = (creditsUsed / creditsTotal) * 100.0
        }

        // -- Managed plan with no usage (e.g. "Managed by Admin") --
        let isManagedPlan = stripped.lowercased().contains("managed by admin")
            || stripped.lowercased().contains("managed by organization")
        let isNewFormat = firstCapture(in: stripped, pattern: #"Plan:[ \t]*(.+)"#) != nil
        if isNewFormat, isManagedPlan, !matchedPercent, !matchedCredits {
            let window = QuotaWindow(label: "Credits", usedPct: 0, remainingPct: 100)
            return ProviderStatus(
                id: "kiro", displayName: "Kiro",
                windows: [window], lastUpdated: Date(), error: nil,
                accountLabel: accountEmail, planName: planName)
        }

        guard matchedPercent || matchedCredits else {
            throw KiroProviderError.parseError("Không tìm thấy thông tin usage trong output kiro-cli")
        }

        let usedPct = max(0, min(100, Int(creditsPercent.rounded())))
        let remainingPct = 100 - usedPct

        // -- Overage (pay-as-you-go beyond the plan), ported from CodexBar --
        let overageCreditsUsed = firstCapture(in: stripped, pattern: #"(?i)Credits used:\s*(\d+\.?\d*)"#).flatMap(Double.init)
        let overageCostUSD = firstCapture(in: stripped, pattern: #"(?i)Est\.\s*cost:\s*\$?(\d+\.?\d*)\s*USD"#).flatMap(Double.init)
        let manageURL = firstCapture(in: stripped, pattern: #"https://app\.kiro\.dev/account/usage"#)

        // Subtitle: "X.XX / Y credits"; add a manage hint once credits run out.
        var subtitle: String? = matchedCredits
            ? String(format: "%.2f / %.0f credits", creditsUsed, creditsTotal)
            : nil
        if remainingPct == 0, manageURL != nil {
            subtitle = [subtitle, "Nâng cấp tại app.kiro.dev"].compactMap { $0 }.joined(separator: " · ")
        }

        let creditsWindow = QuotaWindow(
            label: "Credits",
            usedPct: usedPct,
            remainingPct: remainingPct,
            subtitle: subtitle,
            resetDate: resetDate)

        // Bonus credits window (if present)
        var windows: [QuotaWindow] = [creditsWindow]
        if let bonus = parseBonusCredits(from: stripped) {
            let bonusUsedPct = bonus.total > 0
                ? max(0, min(100, Int((bonus.used / bonus.total * 100).rounded())))
                : 0
            let bonusExpiry: Date? = bonus.expiryDays.flatMap {
                Calendar.current.date(byAdding: .day, value: $0, to: Date())
            }
            let bonusWindow = QuotaWindow(
                label: "Bonus Credits",
                usedPct: bonusUsedPct,
                remainingPct: 100 - bonusUsedPct,
                subtitle: String(format: "%.2f / %.0f bonus", bonus.used, bonus.total),
                resetDate: bonusExpiry)
            windows.append(bonusWindow)
        }

        // Overage window — only when the plan reports pay-as-you-go usage.
        if overageCostUSD != nil || overageCreditsUsed != nil {
            var parts: [String] = []
            if let u = overageCreditsUsed { parts.append(String(format: "%.2f credits", u)) }
            if let c = overageCostUSD { parts.append(String(format: "~$%.2f", c)) }
            windows.append(QuotaWindow(
                label: "Vượt hạn mức",
                usedPct: 0, remainingPct: 100,
                subtitle: parts.isEmpty ? "Đang bật" : parts.joined(separator: " · ")))
        }

        // Structured payload for the menu-bar display-mode picker.
        let kiroMenu = KiroMenuUsage(
            creditsRemaining: creditsTotal - creditsUsed,
            creditsUsed: matchedCredits ? creditsUsed : nil,
            creditsTotal: matchedCredits ? creditsTotal : nil,
            primaryRemainingPct: remainingPct,
            overageCreditsUsed: overageCreditsUsed,
            overageCostUSD: overageCostUSD)

        return ProviderStatus(
            id: "kiro", displayName: "Kiro",
            windows: windows, lastUpdated: Date(), error: nil,
            accountLabel: accountEmail,
            creditsRemaining: creditsTotal - creditsUsed,
            planName: planName,
            kiroMenu: kiroMenu)
    }

    // MARK: - Parse helpers

    private static func parsePlanName(from text: String) -> String {
        // New format: "Plan: Q Developer Pro"
        if let cap = firstCapture(in: text, pattern: #"Plan:[ \t]*(.+)"#) {
            let line = cap.components(separatedBy: "\n").first ?? cap
            let cleaned = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty { return cleaned }
        }
        // kiro-cli 2.x: "Estimated Usage | resets on 2026-06-01 | KIRO FREE"
        if let m = text.range(of: #"Estimated Usage[ \t]*\|[^\n|]*\|[ \t]*([A-Z][A-Z0-9 ]+)"#, options: .regularExpression) {
            let line = String(text[m])
            if let plan = line.split(separator: "|").last?.trimmingCharacters(in: .whitespacesAndNewlines), !plan.isEmpty {
                return formatPlanName(plan)
            }
        }
        // Legacy: "| KIRO FREE"
        if let m = text.range(of: #"\|[ \t]*(KIRO[ \t]+\w+)"#, options: .regularExpression) {
            let raw = String(text[m]).replacingOccurrences(of: "|", with: "").trimmingCharacters(in: .whitespaces)
            return formatPlanName(raw)
        }
        return "Kiro"
    }

    private static func formatPlanName(_ raw: String) -> String {
        // "KIRO FREE" → "Kiro Free"
        raw.split(separator: " ").map { word in
            if word.caseInsensitiveCompare("KIRO") == .orderedSame { return "Kiro" }
            return word.prefix(1).uppercased() + word.dropFirst().lowercased()
        }.joined(separator: " ")
    }

    private static func parseResetDate(from text: String) -> Date? {
        // "resets on YYYY-MM-DD" or "resets on MM/DD"
        guard let m = text.range(of: #"resets on (\d{4}-\d{2}-\d{2}|\d{2}/\d{2})"#, options: .regularExpression) else {
            return nil
        }
        let seg = String(text[m])
        guard let dateRange = seg.range(of: #"\d{4}-\d{2}-\d{2}|\d{2}/\d{2}"#, options: .regularExpression) else {
            return nil
        }
        return parseDateString(String(seg[dateRange]))
    }

    private static func parseDateString(_ s: String) -> Date? {
        if s.contains("-") {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone.current
            f.dateFormat = "yyyy-MM-dd"
            return f.date(from: s)
        }
        // MM/DD — assume current or next year
        let parts = s.split(separator: "/")
        guard parts.count == 2,
              let month = Int(parts[0]), let day = Int(parts[1]) else { return nil }
        let cal = Calendar.current
        let now = Date()
        var comps = DateComponents()
        comps.month = month; comps.day = day
        comps.year = cal.component(.year, from: now)
        if let d = cal.date(from: comps), d > now { return d }
        comps.year = (comps.year ?? 0) + 1
        return cal.date(from: comps)
    }

    private static func parseBonusCredits(from text: String) -> (used: Double, total: Double, expiryDays: Int?)? {
        guard let m = text.range(of: #"Bonus credits:\s*(\d+\.?\d*)/(\d+)"#, options: .regularExpression) else {
            return nil
        }
        let seg = String(text[m])
        let nums = extractNumbers(seg)
        guard nums.count >= 2 else { return nil }
        var expiry: Int?
        if let em = text.range(of: #"expires in (\d+) days?"#, options: .regularExpression) {
            let eseg = String(text[em])
            if let nm = eseg.range(of: #"\d+"#, options: .regularExpression) {
                expiry = Int(String(eseg[nm]))
            }
        }
        return (nums[0], nums[1], expiry)
    }

    private static func firstCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let r = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractNumbers(_ text: String) -> [Double] {
        // Extracts all decimal numbers from a string
        let pattern = #"\d+\.?\d*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match -> Double? in
            guard let r = Range(match.range, in: text) else { return nil }
            return Double(String(text[r]))
        }
    }

    // MARK: - Error helper

    private func failure(_ message: String) -> ProviderStatus {
        ProviderStatus(id: id, displayName: displayName, windows: [], lastUpdated: Date(), error: message)
    }
}

// MARK: - Internal error type

private enum KiroProviderError: Error {
    case binaryNotFound
    case notLoggedIn
    case cliFailed(String)
    case parseError(String)
    case timeout

    var localizedMessage: String {
        switch self {
        case .binaryNotFound:
            "Chưa cài Kiro CLI"
        case .notLoggedIn:
            "Chưa đăng nhập Kiro. Chạy 'kiro-cli login' trong Terminal"
        case let .cliFailed(msg):
            "Kiro CLI lỗi: \(msg)"
        case let .parseError(msg):
            "Parse thất bại: \(msg)"
        case .timeout:
            "Kiro CLI timeout"
        }
    }
}
