# Development Roadmap

## Phase 0 — Bootstrap (in_progress)
- [x] Scout codebase + research CodexBar / MiniMax quota
- [x] Design kiến trúc, 4-point review
- [ ] Viết `specs/ai-statusbar/` (spec.json + design.md + tasks/)
- [ ] Setup Xcode project (macOS app, SwiftUI, MenuBarExtra)

## Phase 1 — Quota providers
- [ ] Provider protocol + `ProviderStatus` model
- [ ] `MiniMaxProvider` gọi `/v1/token_plan/remains`
- [ ] `HapoHubProvider` (mock trước, endpoint thật sau khi BOSS cung cấp)
- [ ] `QuotaService` poll 60s + cache + publish

## Phase 2 — UI quota
- [ ] `MenuBarExtra` shell + popover
- [ ] `QuotaPanel` + `ProviderRow` + `QuotaBar` (progress %)
- [ ] Icon menu bar cập nhật theo % thấp nhất
- [ ] Settings: thêm/sửa provider, lưu Keychain

## Phase 3 — Config Claude Code
- [ ] `ConfigService` đọc/ghi `~/.claude/settings.json` + backup `.bak`
- [ ] `ConfigPanel` form global (env, permissions, plugins)
- [ ] Per-project: scan `~/.claude/projects/`, sửa theo project
- [ ] Mask API key

## Phase 4 — Verify & polish
- [ ] `xcodebuild` build clean
- [ ] Test e2e: poll quota, đổi model, restart app giữ state
- [ ] Edge cases: token sai, mạng lỗi, settings.json hỏng
