# Provider Parity Audit — BirdNion vs CodexBar

> Ngày: 2026-06-28. Phạm vi: 22 provider của BirdNion, so với bản tham chiếu CodexBar (`~/Desktop/CodexBar`). Audit **chỉ đọc**, không sửa code.
> Mục tiêu: kiểm tra **cách lấy dữ liệu (fetch)** và **cách hiển thị UI** của từng provider đã giống CodexBar chưa.

## Trạng thái triển khai (2026-06-28)

Đã thực hiện theo wave, build + 90/90 test xanh sau mỗi wave:
- **Wave 1 — cosmetics (21 provider)**: displayName + brand tint + dashboard/status links theo đúng CodexBar.
- **Wave 2-3 — 14 provider**: ElevenLabs (pro voices+status), Groq (cache-hits+tách window), OpenRouter (/key+env), DeepSeek (granted/topped_up+balance≤0+env), CommandCode (lọc cookie session), OpenCode/OpenCodeGo ("Gia hạn" renewAt), Deepgram (aggregate tất cả project+metrics), Gemini (3-tier Pro/Flash/Flash-Lite+Workspace), Zai (computedUsedPercent+phân loại window), Kiro (overage+manageURL), Kilo (CLI source+auto top-up), Cursor (Auto/API lanes+legacy requests), Copilot (username thật+enterprise host+budget extras).
- **Wave 4 — 5 provider lớn**: Codex (chatgpt_base_url + decode unlimited/has_credits + email-ownership), Bedrock (Cost Explorer $ + budget + region từ config), Antigravity (agy CLI warm-session + account-match guard), MiniMax (cookie/web fallback + points + subscription), Alibaba (Coding Plan 5h/Tuần/Tháng + sec_token mở rộng).
- **Wave 5 — UI**: render Codex extras trong popover (credits ∞ / version / service-status badge / code-review % / reset-credits).

**Bổ sung sau (deferred → đã làm)**: Alibaba region picker (intl/cn), Bedrock budget config field + UI, ElevenLabs env override, Deepgram Project-ID field, Antigravity Google OAuth (loopback + tự trích client từ Antigravity.app), Copilot OAuth Device Flow + enterprise host, **Kilo usage source picker (Auto/API/CLI) + Organizations (scope picker + refresh + CLI `kilo.access` parse + `X-KILOCODE-ORGANIZATIONID`)**, + fixture test parser mới (ElevenLabs pro-voices, DeepSeek granted/low-balance, OpenCode renewAt, Kilo org tRPC/REST). Tổng 94 test xanh.

**Settings UI parity (3 provider HARD)**: thay ô Token generic (sai) bằng UI đúng — **Gemini**: sign-in status Google (đọc email từ `~/.gemini/oauth_creds.json`) + hint CLI; **Kiro**: hint Kiro CLI (không token); **Bedrock**: auth-mode picker (Access keys / AWS profile) + Access key ID/Secret (secure) hoặc Profile name + Region field, wire `AWSCredentialReader` đọc config trước (giữ fallback env/~/.aws). Config thêm field `secretKey`/`awsAuthMode`/`awsProfile`.

**Menu-bar parity (gemini/kiro/bedrock)**: thêm **"Menu bar metric"** picker generic (`MenuBarMetricStore`, Automatic = mọi window, hoặc 1 window theo label) cho 3 provider. **Kiro "menu bar value"**: đủ **9 mode** (Automatic/Hidden/Credits left/Percent/Credits+percent/Used÷total/3× overage) — thêm `KiroMenuUsage` vào `ProviderStatus`, Kiro phơi credits/overage, `Frame.provider` thêm `text` override, render trong AppDelegate. Test `testKiroMenuBarDisplayModes` (95 test xanh).

**Còn deferred (giá trị thấp / cần OAuth nặng — sẽ làm khi BOSS yêu cầu)**: Gemini curl-fallback (chỉ chống timeout) + Google login loopback (hiện đăng nhập qua Gemini CLI), Bedrock SSO/assume-role qua `aws configure export-credentials` (hiện chỉ static keys), Kilo multi-org fan-out (mỗi org 1 row — hiện 1 scope active), Zai model-usage hourly chart, MiMo local-cache fallback, Cursor cookie-cache/stored-session.

> ⚠️ 4 provider auth nặng (Bedrock/Antigravity/MiniMax/Alibaba) + cookie/CLI mới đã build-verify nhưng CẦN BOSS test live (credentials thật) để xác nhận.

## Kiến trúc khác biệt (đọc trước)

| | CodexBar | BirdNion |
|---|---|---|
| Tổ chức 1 provider | tách nhiều file: `*UsageFetcher`/`*StatusProbe` (logic), `*UsageSnapshot` (model), `*ProviderDescriptor` (branding/UI), `*ProviderImplementation` (glue→menu) | gộp 1 file `<X>Provider.swift` |
| Model hiển thị | `UsageSnapshot{primary, secondary, tertiary, extraRateWindows, identity, providerCost…}` | `ProviderStatus{windows[], cost?, creditsRemaining?, planName?, accountLabel?, webExtras?}` |
| Render | menu generic theo descriptor + cosmetics riêng | `QuotaPanel.swift` render generic; mọi window nhồi vào `windows[]` |

→ Hệ quả lặp lại: BirdNion thiếu `tertiary`/`extraRateWindows` riêng nên **gộp nhiều window vào ít window**; nhiều field đã fetch nhưng **không có chỗ trên UI để render** (rõ nhất ở Codex).

## Scoreboard

| Verdict | Count | Provider |
|---|---|---|
| ✅ FULL | 0 | — |
| 🟡 PARTIAL | 14 | ElevenLabs, Groq, Kilo, CommandCode, MiMo, OpenCode, OpenCodeGo, Gemini, Kiro, Codex, Claude, OpenRouter, DeepSeek, Zai |
| 🔴 DIVERGE/MISSING | 7 | Deepgram, Copilot, Alibaba, Cursor, Antigravity, Bedrock, MiniMax |
| N/A | 1 | Hapo (không có ở CodexBar) |

Provider gần parity nhất: **Claude** (UI thậm chí superset — có cost chart + admin chart). Provider lệch nặng nhất: **Bedrock** (sai nguồn dữ liệu), **Antigravity** (thiếu 2/3 chiến lược), **MiniMax** (thiếu web/cookie auth).

## Gap xuyên suốt (sửa 1 lần, ăn nhiều provider)

1. **Thiếu dashboard/status link** — gần như TẤT CẢ provider mới + nhiều provider gốc. CodexBar mỗi descriptor đều có link "Open dashboard"; BirdNion `ProvidersPane.dashboardLinks(for:)` trả `[]`. → quick win UI lớn nhất.
2. **Brand tint lệch/thiếu** — Deepgram, Copilot, Kilo, Gemini, Kiro, Antigravity, Bedrock (thiếu màu); Codex (blue vs teal); MiniMax (nghi dùng nhầm màu mimo). CodexBar lấy từ `ProviderBranding.color`.
3. **displayName lệch nhãn** — Copilot ("GitHub Copilot"→"Copilot"), Kilo ("Kilo Code"→"Kilo"), CommandCode ("CommandCode"→"Command Code"), MiMo ("MiMo"→"Xiaomi MiMo"), Zai ("Z.ai / GLM"→"z.ai").
4. **Gộp window** — Groq (gộp req+tok), Gemini (N model thô thay vì 3 tier Pro/Flash/Flash-Lite), Cursor (gộp Auto/API lanes), OpenCode/OpenCodeGo (thiếu "Renews" window).
5. **Thiếu endpoint enrichment phụ** — OpenRouter `/key`, DeepSeek usage/cost, Zai model-usage, Deepgram aggregate-all-projects, Groq cache-hits.

## Phân loại theo độ ưu tiên sửa

### P1 — Quick win cosmetics (UI giống ngay, ít rủi ro)
Dashboard links + brand tints + displayName cho toàn bộ. Chỉ động `ProvidersPane.swift` + `QuotaPanel.VocabbyTheme`. ~1 buổi.

### P2 — Sai/thiếu dữ liệu hiển thị nhưng đã fetch
- **Codex**: render credits/∞, code-review %, version, service badge, reset-credits, dashboard (đã fetch, UI bỏ).
- Window granularity: Groq tách window, Gemini 3-tier, Cursor Auto/API lanes, OpenCode(Go) "Renews".

### P3 — Divergence fetch (cần port thêm logic, scope lớn)
- **Bedrock**: thêm Cost Explorer ($ spend + budget) + auth-mode picker + region UI. (Hiện chỉ CloudWatch tokens — sai nguồn.)
- **Deepgram**: aggregate tất cả project (đang chỉ lấy project đầu).
- **Alibaba**: thêm biến thể Coding Plan (5h/Weekly/Monthly + region intl/cn).
- **Cursor**: legacy request plan + cookie names/domains mở rộng.
- **Copilot**: budget extras + enterprise host + GitHub username thật.
- **Antigravity**: CLI warm-session + OAuth multi-account + account-match guard.
- **MiniMax**: web/cookie auth + billing/points/subscription.

## Chi tiết từng provider
- [Batch A — EASY: ElevenLabs, Deepgram, Groq, Copilot, Kilo](./batch-a-easy.md)
- [Batch B — Cookie: CommandCode, MiMo, Alibaba, OpenCode, OpenCodeGo, Cursor](./batch-b-cookie.md)
- [Batch C — HARD: Gemini, Kiro, Antigravity, Bedrock](./batch-c-hard.md)
- [Batch D — Gốc: Codex, Claude, MiniMax, OpenRouter, DeepSeek, Zai, Hapo](./batch-d-original.md)

## Câu hỏi cần BOSS quyết
1. Có làm P1 (cosmetics: link + tint + displayName toàn bộ) trước không? (khuyến nghị: có)
2. Các divergence P3 — làm hết để đạt full parity, hay chỉ làm provider BOSS thực sự dùng?
3. Bedrock: đổi sang Cost Explorer ($) như CodexBar, hay giữ CloudWatch tokens?
