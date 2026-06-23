# AI Statusbar — System Architecture

> Menu bar app macOS native (Swift + SwiftUI), hiển thị quota AI của nhiều hệ thống và sửa config Claude Code.

## 1. Mục tiêu

App nhỏ chạy trên thanh menu macOS (icon góc phải, popover), theo dõi quota AI của các hệ thống BOSS dùng/vận hành, đồng thời cung cấp UI sửa config Claude Code global + per-project.

## 2. Stack & phạm vi

- **Stack**: Swift + SwiftUI, `MenuBarExtra` (macOS 13+), Xcode 15+
- **Triển khai**: cá nhân, 1 máy. Không cần code sign/notarize.
- **Out of scope**: đa người dùng, phân phối, auto-update.

## 3. Provider quota

### 3.1 Mô hình dữ liệu thống nhất

```swift
struct QuotaWindow {
  let label: String     // vd "5 giờ", "Tuần"
  let usedPct: Int      // đã dùng 0-100
  let remainingPct: Int // còn lại 0-100
}

struct ProviderStatus {
  let id: String        // "minimax", "hapo", ...
  let displayName: String
  let windows: [QuotaWindow]
  let lastUpdated: Date
  let error: String?    // nil = OK
}
```

### 3.2 Protocol

```swift
protocol QuotaProvider {
  var id: String { get }
  var displayName: String { get }
  func fetch() async throws -> ProviderStatus
}
```

### 3.3 Provider built-in

**MiniMaxProvider** (id: `minimax`)

- Endpoint: `GET https://api.minimax.io/v1/token_plan/remains`
- Auth: `Authorization: Bearer <Subscription Key>` (chính là API key BOSS dùng cho `/v1/chat/completions`)
- Response shape (đã verify từ MiniMax-M2.7 issue #48):
  ```json
  {
    "model_remains": [
      {
        "model_name": "general",
        "current_interval_total_count": <int>,
        "current_interval_usage_count": <int>,
        "current_interval_remaining_percent": <int 0-100>,
        "current_weekly_total_count": <int>,
        "current_weekly_usage_count": <int>,
        "current_weekly_remaining_percent": <int 0-100>
      }
    ]
  }
  ```
- Mapping: trả về **2 window**:
  - `"5 giờ"` → `current_interval_remaining_percent`
  - `"Tuần"` → `current_weekly_remaining_percent`
- Có thể có nhiều model trong `model_remains`; MVP lấy model đầu tiên.

**HapoHubProvider** (id: `hapo`)

- Endpoint: **TODO: BOSS cung cấp** (khi implement sẽ xin endpoint + header auth + JSON mẫu).
- Có mock provider nội bộ trả dữ liệu giả để test UI trong khi chờ.

## 4. Luồng quota

```
QuotaService
  ├─ Timer 60s (configurable)
  ├─ Gọi song song mọi provider (TaskGroup)
  ├─ Cache kết quả theo id
  ├─ Publish @Published [ProviderStatus] cho UI
  └─ Cập nhật icon menu bar (badge % thấp nhất hoặc ⚠️ nếu <15%)
```

Xử lý lỗi: lỗi mạng/token sai → trả `error` trong `ProviderStatus`, UI hiển thị inline, không crash.

## 5. Lưu trữ & bảo mật

- **Provider config** (id, displayName, enabled): `~/Library/Application Support/AIStatusbar/providers.json`
- **Token/Subscription Key**: **macOS Keychain** (service: `AIStatusbar`, account: provider id). Không lưu plaintext, không log.
- **Claude Code config** đọc/ghi trực tiếp `~/.claude/settings.json`. **Backup `.bak`** trước mỗi lần ghi.
- API key trong UI hiển thị dạng masked: `fe_oa_••••4a8`.

## 6. Tab Config Claude Code

Form có cấu trúc, không raw text:

**Global** (`~/.claude/settings.json`):
- `env.ANTHROPIC_MODEL` — text field (dropdown gợi ý)
- `env.ANTHROPIC_BASE_URL` — text
- `env.ANTHROPIC_API_KEY` — password (mask)
- `env.ANTHROPIC_DEFAULT_OPUS_MODEL` / `SONNET` / `HAIKU` — text
- `permissions.defaultMode` — segmented (default/acceptEdits/dontAsk/...)
- `enabledPlugins` — toggle list
- `hooks` — không sửa trong MVP (chỉ xem)

**Per-project** (`~/.claude/projects/<encoded>/.claude/settings.json` hoặc `<project>/.claude/settings.json`):
- Dropdown chọn project (scan `~/.claude/projects/`)
- Các field tương tự global
- Sửa field → ghi vào `.claude/settings.json` của project đó (backup trước)

## 7. Cấu trúc module (Swift Package / Xcode)

```
App/
  AIStatusbarApp.swift           // @main, MenuBarExtra
  Views/
    PopoverView.swift
    QuotaPanel.swift
    ConfigPanel.swift
    ProviderRow.swift
    QuotaBar.swift
Services/
  QuotaService.swift             // Timer + cache
  ConfigService.swift            // đọc/ghi settings.json
  KeychainService.swift          // wrapper
Models/
  ProviderStatus.swift
  ClaudeSettings.swift           // Codable models cho ~/.claude/settings.json
Providers/
  QuotaProvider.swift            // protocol
  MiniMaxProvider.swift
  HapoHubProvider.swift
  MockProvider.swift
```

## 8. Acceptance criteria (MVP)

- [ ] App xuất hiện icon ở menu bar, click mở popover
- [ ] Cấu hình được 2 provider (MiniMax + Hapo) trong Settings
- [ ] Token lưu trong Keychain, không có plaintext trong file
- [ ] Quota poll mỗi 60s, hiển thị 2 window cho MiniMax (5h + Tuần)
- [ ] Hapo provider có mock chạy được UI; endpoint thật sẽ cập nhật sau
- [ ] Tab Config đọc được `~/.claude/settings.json`
- [ ] Sửa 1 field global + ghi → backup `.bak` tạo ra, JSON hợp lệ, reload OK
- [ ] Per-project: chọn được project, sửa được model
- [ ] Build `xcodebuild` thành công, app chạy được trên máy BOSS
- [ ] Lỗi mạng không crash, hiện inline trong row

## 9. Decision register

| Quyết định | Nguồn | Lý do |
|---|---|---|
| Swift + SwiftUI, MenuBarExtra | BOSS duyệt | Native, nhẹ, giống CodexBar |
| Cá nhân, không sign/notarize | BOSS duyệt | Phạm vi 1 máy |
| Adapter cấu hình + 2 built-in | Tôi đề xuất, BOSS duyệt | Đa dạng provider không thể hard-code |
| MiniMax quota kiểu rolling 5h + tuần | MiniMax docs/issue #48 | Đây là cách platform chính thức track |
| Token trong Keychain | Best practice macOS | Không lưu plaintext, không log |
| Backup `.bak` trước ghi settings.json | YAGNI an toàn | Tránh hỏng file cấu hình |
| Per-project config trong MVP | BOSS duyệt | Match yêu cầu "global + project" |

## 10. Open questions

- **Hapo Hub endpoint quota**: BOSS sẽ cung cấp sau. Adapter có mock để không chặn MVP.
- **Số lượng model trong `model_remains`**: MiniMax issue chỉ thấy 1 model. MVP lấy model đầu. Sau có thể cho chọn.
- **Refresh interval**: 60s mặc định — confirm với BOSS nếu muốn khác.
