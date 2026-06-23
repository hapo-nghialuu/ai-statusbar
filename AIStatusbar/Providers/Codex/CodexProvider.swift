import Foundation

/// Codex (OpenAI/ChatGPT) usage quota provider.
///
/// Unlike MiniMax/Hapo this is **zero-config**: the OAuth token lives in
/// `~/.codex/auth.json` (written by `codex login`), not in our Keychain. We read
/// it, fetch usage from the ChatGPT backend API, and map the primary/secondary
/// rate-limit windows onto our `QuotaWindow` model.
///
/// Token handling mirrors CodexBar: refresh proactively when stale (>8 days)
/// and write the rotated token back to auth.json. Because we have no Codex CLI
/// fallback, we additionally retry once with a fresh token on a 401.
final class CodexProvider: QuotaProvider {
    let id = "codex"
    let displayName = "Codex"

    private let session: URLSession
    private let authURL: URL

    init(session: URLSession = .shared, authURL: URL = CodexAuthStore.authFileURL()) {
        self.session = session
        self.authURL = authURL
    }

    func fetch() async throws -> ProviderStatus {
        var credentials: CodexCredentials
        do {
            credentials = try CodexAuthStore.load(url: authURL)
        } catch CodexAuthError.notFound, CodexAuthError.missingTokens {
            return failure("Chưa đăng nhập Codex — chạy `codex` để đăng nhập")
        } catch {
            return failure("Không đọc được auth.json")
        }

        // Proactive refresh (like CodexBar): rotate a stale token before it 401s.
        if credentials.needsRefresh, !credentials.refreshToken.isEmpty,
           let refreshed = try? await CodexTokenRefresher.refresh(credentials, session: session)
        {
            credentials = refreshed
            try? CodexAuthStore.save(refreshed, url: authURL)
        }

        do {
            let usage = try await CodexUsageAPI.fetchUsage(
                accessToken: credentials.accessToken,
                accountId: credentials.accountId,
                session: session)
            return success(usage, credentials: credentials)
        } catch CodexUsageError.unauthorized {
            // Reactive refresh + single retry (compensates for no CLI fallback).
            if !credentials.refreshToken.isEmpty,
               let refreshed = try? await CodexTokenRefresher.refresh(credentials, session: session)
            {
                try? CodexAuthStore.save(refreshed, url: authURL)
                if let usage = try? await CodexUsageAPI.fetchUsage(
                    accessToken: refreshed.accessToken,
                    accountId: refreshed.accountId,
                    session: session)
                {
                    return success(usage, credentials: refreshed)
                }
            }
            return failure("Token Codex hết hạn — chạy `codex` để đăng nhập lại")
        } catch CodexUsageError.serverError(let code) {
            return failure("HTTP \(code)")
        } catch CodexUsageError.invalidResponse {
            return failure("Response không hợp lệ")
        } catch {
            return failure("Network: \(error.localizedDescription)")
        }
    }

    // MARK: - Mapping

    /// Pure mapping (unit-testable): primary window → session (~5h), secondary → weekly.
    static func map(_ usage: CodexUsageResponse) -> [QuotaWindow] {
        var windows: [QuotaWindow] = []
        if let primary = usage.rateLimit?.primaryWindow {
            windows.append(window(primary, label: "5 giờ"))
        }
        if let secondary = usage.rateLimit?.secondaryWindow {
            windows.append(window(secondary, label: "Tuần"))
        }
        return windows
    }

    private static func window(_ w: CodexUsageResponse.Window, label: String) -> QuotaWindow {
        let used = max(0, min(100, w.usedPercent))
        return QuotaWindow(
            label: label,
            usedPct: used,
            remainingPct: 100 - used,
            resetDate: Date(timeIntervalSince1970: TimeInterval(w.resetAt)))
    }

    private func success(_ usage: CodexUsageResponse, credentials: CodexCredentials) -> ProviderStatus {
        let windows = Self.map(usage)
        guard !windows.isEmpty else {
            return failure("Codex chưa có dữ liệu quota")
        }
        return ProviderStatus(
            id: id,
            displayName: displayName,
            windows: windows,
            lastUpdated: Date(),
            error: nil,
            accountLabel: accountLabel(credentials))
    }

    private func failure(_ message: String) -> ProviderStatus {
        ProviderStatus(id: id, displayName: displayName, windows: [], lastUpdated: Date(), error: message)
    }

    /// User override (providers.json) wins; otherwise the account email from the
    /// id_token; otherwise a static fallback.
    private func accountLabel(_ credentials: CodexCredentials) -> String {
        if let override = ProvidersStore.load().providers.first(where: { $0.id == id })?.accountLabel,
           !override.isEmpty
        {
            return override
        }
        return CodexAuthStore.emailFromIDToken(credentials.idToken) ?? "Codex"
    }
}
