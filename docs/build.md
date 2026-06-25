# Build & Release

## Yêu cầu
- macOS 14+ (Sonoma). Một số API dùng `@Environment` SwiftUI 5.
- Xcode 15+ (đã verify với Xcode 16/26). Command Line Tools: `xcode-select --install`.
- [Homebrew](https://brew.sh) + [GitHub CLI](https://cli.github.com) (`brew install gh`) cho release flow.
- Không cần dependency ngoài SwiftUI / AppKit / UserNotifications / Foundation — nhưng project link local SPM [CodexBarCore](https://github.com/hapo-nghialuu/CodexBar) tại `~/Desktop/CodexBar` (xem `project.pbxproj`).

## Mở project
```bash
open AIStatusbar.xcodeproj
```
Trong Xcode chọn scheme `AIStatusbar` → Run (⌘R). App chạy dạng menu-bar only (LSUIElement).

## Build từ CLI

```bash
# Debug build (nhanh)
xcodebuild build -project AIStatusbar.xcodeproj -scheme AIStatusbar \
  -configuration Debug -destination 'platform=macOS'

# Release build (binary tối ưu, dùng để deploy ~/Desktop/BirdNion.app)
xcodebuild build -project AIStatusbar.xcodeproj -scheme AIStatusbar \
  -configuration Release -destination 'platform=macOS'
```

**Lưu ý**: Sau khi đổi `project.pbxproj` (thêm file, thay đổi build settings) → cần `clean` để tránh linker error từ `.o` cũ.

```bash
xcodebuild clean build -project AIStatusbar.xcodeproj -scheme AIStatusbar \
  -configuration Release -destination 'platform=macOS'
```

## Chạy test
```bash
xcodebuild test -project AIStatusbar.xcodeproj -scheme AIStatusbar \
  -configuration Debug -destination 'platform=macOS'
```

Filter theo class / function:
```bash
xcodebuild test ... -only-testing:AIStatusbarTests/CodexBarConfigStoreTests
xcodebuild test ... -only-testing:AIStatusbarTests/MenuBarVisibilityTests
```

## Deploy local — `~/Desktop/BirdNion.app`

Bundle name `BirdNion.app` đặt trong pbxproj (`PRODUCT_NAME = AIStatusbar` cho binary để giữ UserDefaults + Keychain service name ổn định qua các version).

```bash
SRC=~/Library/Developer/Xcode/DerivedData/AIStatusbar-bnhvrpmimlkomagvqedntylrgzmu/Build/Products/Release/AIStatusbar.app
DST=~/Desktop/BirdNion.app

pkill -x AIStatusbar 2>/dev/null; sleep 0.5
rm -rf "$DST"
cp -R "$SRC" "$DST"
open "$DST"
```

Tìm nhanh khi DerivedData path đổi:
```bash
find ~/Library/Developer/Xcode/DerivedData -type d -name AIStatusbar.app -path "*Release*"
```

## Release — push lên Homebrew tap

Dùng script tự động (xem [release flow](#release-flow) bên dưới):

```bash
Scripts/release.sh 0.3.0
# 6 bước tự động:
#   1. Verify clean working tree
#   2. Bump MARKETING_VERSION + CFBundleShortVersionString
#   3. xcodebuild Release
#   4. Copy + zip + shasum
#   5. gh release upload lên hapo-nghialuu/homebrew-tap
#   6. Update + push Casks/birdnion.rb với version + SHA mới
```

### Release flow

```
[Local]                    [GitHub: homebrew-tap]
─────────                   ──────────────────────
build/zip
  │
  ├─► gh release create vX.Y.Z + upload zip
  │     │
  │     └─► Release page (zip available)
  │
  └─► update Casks/birdnion.rb:
       version, sha256, url
       git commit + push
              │
              └─► User: brew install --cask hapo-nghialuu/tap/birdnion
                     → downloads zip
                     → copies to /Applications
                     → postflight: xattr -dr com.apple.quarantine
                     → opens app, no Gatekeeper dialog
```

### Verify sau khi release

```bash
brew reinstall hapo-nghialuu/tap/birdnion
xattr -l /Applications/BirdNion.app   # should NOT contain com.apple.quarantine
plutil -p /Applications/BirdNion.app/Contents/Info.plist | grep CFBundleShortVersionString
```

## Code signing

Hiện tại **ad-hoc signed** (`Sign to Run Locally`). Cách bypass Gatekeeper:

- `Scripts/release.sh` đã thêm `postflight do … xattr -dr com.apple.quarantine` nên user mở thẳng, không cần Right-click → Open.

Để user mở thẳng **không cần** postflight (và không cần `xattr` hack), cần:

1. **Apple Developer Program** ($99/năm) — https://developer.apple.com/programs/
2. Tạo **Developer ID Application** cert trong Xcode → Keychain
3. Setup notarization credentials:
   ```bash
   xcrun notarytool store-credentials "AC_PASSWORD" \
     --apple-id your@email.com --team-id TEAMID
   ```
4. Update `Scripts/release.sh` (sau đoạn `xcodebuild`, trước `zip`):
   ```bash
   codesign --deep --force --options runtime \
     --sign "Developer ID Application: TÊN BẠN (TEAMID)" \
     "$DESKTOP/BirdNion.app"
   ditto -c -k --sequesterRsrc --keepParent \
     "$DESKTOP/BirdNion.app" "$DESKTOP/BirdNion.zip"
   xcrun notarytool submit "$DESKTOP/BirdNion.zip" --wait
   rm "$DESKTOP/BirdNion.zip"
   ```
5. Drop the `postflight xattr` block (no longer needed).

## Provider tokens & config

| Token | Location | Override env |
|---|---|---|
| MiniMax, Hapo, OpenRouter, DeepSeek, Z.ai | `~/.config/codexbar/config.json` (XDG) hoặc `~/.codexbar/config.json` (legacy) | `MINIMAX_CODING_API_KEY`, `MINIMAX_API_KEY` |
| Claude OAuth | macOS Keychain `service: Claude Code-credentials` | (re-login via `claude` CLI) |
| Codex OAuth | `~/.codex/auth.json` | (re-login via `codex` CLI) |
| Per-provider enable/visibility | `~/Library/Application Support/AIStatusbar/providers.json` | (Settings sidebar) |
| Per-provider menu-bar visibility | UserDefaults `menuBarVisibility.<id>` | (Settings popover switch) |
| Per-provider refresh interval | UserDefaults `refreshInterval.<id>` | (Settings popover picker) |
| General settings (region, refresh, ...) | UserDefaults (key prefix = bundle id) | (Settings general pane) |

## Troubleshooting

| Lỗi | Nguyên nhân | Cách xử lý |
|---|---|---|
| `linkd` error spam trong test log | System service macOS, vô hại | Bỏ qua — `grep -v "linkd"` |
| `Unable to find module dependency: 'AIStatusbar'` | Test chạy trước khi app build | `xcodebuild build` trước, rồi `test` |
| Linker error `Undefined symbols ...` | Build incremental sau khi đổi `init` | `xcodebuild clean build` rồi test |
| `release.sh` SHA mismatch on upload | GitHub release-asset cache | Đổi filename (`v0.x.y` → `0.x.y`) — script tự dùng `BirdNion-${VERSION}.zip` |
| BirdNion mở ra dialog Gatekeeper | postflight chưa chạy / cask version cũ | `brew reinstall --cask hapo-nghialuu/tap/birdnion` |
| App icon trắng trong Finder | `ASSETCATALOG_COMPILER_APPICON_NAME` chưa set = `AppIcon` | Check project.pbxproj (đã fix ở `5e8ee0a`) |
| Claude tab "Đang tải…" load lâu | OAuth + cookie fetch chậm khi cold | Đặt `refreshInterval.claude` lớn hơn (UI: Settings popover) |

## File liên quan

- `AIStatusbar.xcodeproj/project.pbxproj` — Xcode project, build settings
- `Scripts/release.sh` — release automation
- `docs/build.md` — file này
- `docs/system-architecture.md` — kiến trúc providers
- `docs/development-roadmap.md` — phases đã xong + còn lại
- External: [homebrew-tap](https://github.com/hapo-nghialuu/homebrew-tap) — Cask + releases
