# Batch D — Provider gốc (7)

Codex · Claude · MiniMax · OpenRouter · DeepSeek · Zai · Hapo
Kết: **0 full / 5 partial / 1 diverge / 1 N/A (Hapo).**

Chung: BirdNion render `ProviderStatus` generic; provider nhỏ chỉ điền `windows`+`accountLabel`+`planName`; field cost/credits/billing của CodexBar không có chỗ hiển thị tương ứng (trừ Claude).

---

## Codex 🟡 PARTIAL
- **Auth**: `~/.codex/auth.json` (honor `CODEX_HOME`), `OPENAI_API_KEY`, OAuth + `account_id`, proactive refresh >8 ngày, reactive refresh + retry 401 (`CodexProvider.swift:88-103`) — MATCH (CodexBar phân loại lỗi refresh expired/revoked/reused chi tiết hơn).
- **Endpoints/flow**: Usage API + reset-credits + app-server RPC (`initialize→initialized→account/rateLimits/read+account/read`) MATCH 1:1. GAP: hardcode host `chatgpt.com` (`CodexUsageAPI.swift:198`), **không hỗ trợ `chatgpt_base_url`** từ config.toml (CodexBar `:370-417`) → enterprise/proxy sai. Web dashboard bỏ tầng `CodexDashboardAuthority` (không check email-ownership → rủi ro nhầm account, `CodexWebDashboard.swift:47-55`).
- **Parsing/data**: RateWindow normalizer port 1:1 (BirdNion thêm clamp). Plan formatting PARTIAL (CodexBar enum PlanType đầy đủ; BirdNion map string). Credits GAP: không decode `unlimited`/`has_credits` từ OAuth (`:69-86`) → account unlimited hiển thị số balance vô nghĩa thay vì "∞".
- **UI fields**: điền đủ (`planType, creditsRemaining, version, serviceStatus/Level, accountID, resetCreditsAvailable, sourceLabel, codexWeb`) NHƯNG **QuotaPanel KHÔNG render**: code-review % (`codexWeb.codeReviewRemainingPercent`), credits balance/∞, resetCreditsAvailable, version, service badge, credits-history/buy-credits link. `metadataParts` chỉ account+plan+source+updated (`QuotaPanel.swift:335-348`). MenuBar thiếu credits-fallback khi mọi window=0%.
- **Cosmetics**: displayName MATCH. tint **blue #0A84FF** khác CodexBar teal rgb(73,163,176). "Open dashboard" link THIẾU. Source picker Auto/OAuth/CLI ✓; multi-account switcher ✓.
- **Gaps**: (1) `chatgpt_base_url` (`:198`); (2) decode `has_credits`+`unlimited` (`:69-86`); (3) render credits/version/code-review/reset/service-badge/dashboard (QuotaPanel); (4) email-ownership check (`CodexWebDashboard.swift:47-55`); (5) menu-bar credits fallback.

## Claude 🟡 PARTIAL (parity tốt nhất — UI superset)
- **Auth**: env → `~/.claude/.credentials.json` → Keychain (`ClaudeOAuth.swift:110-120`), refresh `platform.claude.com/v1/oauth/token`. CodexBar thêm memory-cache TTL + KeychainCacheStore + owner-aware refresh + refresh-failure-gate + fingerprint/cooldown. BirdNion **chủ ý bỏ** hardening (comment `:6-7`).
- **Endpoints/flow**: tất cả core MATCH (OAuth `/api/oauth/usage`, web `/api/organizations`+`/usage`+`/api/account`, admin `cost_report`+`usage_report/messages`). BirdNion **superset**: fetch live service-status `status.anthropic.com/api/v2/summary.json` (CodexBar chỉ link tĩnh).
- **Parsing/data**: window mapping MATCH (primary=five_hour??seven_day, spend-limit fallback, cost cents→USD). Cố ý khác: BirdNion giữ Opus window riêng + Sonnet thành extra window; CodexBar gộp 1 window "Sonnet". Daily Routines extra MATCH. Admin 30-day per-model/cost MATCH.
- **UI fields**: render **nhiều hơn** — popover có local 30-day cost chart (`ClaudeUsageChartCard`) + admin org chart (`ClaudeAdminUsageChartCard`); Settings webExtras/extraRateWindow/cost rows. KHÔNG thiếu dữ liệu hiển thị.
- **Cosmetics**: displayName/tint `#CC7C5E` MATCH. Source + cookie source (lộ cả "Off") + multi-account switcher (add/remove/setActive + Web/Admin kind) đạt/giàu hơn. GAP: links chỉ `status.anthropic.com` (`ProvidersPane.swift:1466-1468`); CodexBar thêm `console.anthropic.com/settings/billing` + `claude.ai/settings/usage` + changelog.
- **Gaps**: (1) thêm 2 dashboard link (`:1466-1468`); (2) (optional) Admin-key secure field độc lập; (3) auth-hardening để nguyên trừ khi thấy re-auth churn.

## MiniMax 🔴 DIVERGE/MISSING
- **Auth**: BirdNion = chỉ API token Bearer (`MiniMaxProvider.swift:121-131`), env MINIMAX_*. CodexBar = **3 mode** (auto/web/api): API token + **cookie/web scraping** (browser import Safari/Chrome, `HERTZ-SESSION`, access-token localStorage, GroupId). → thiếu toàn bộ nhánh web/cookie.
- **Endpoints/flow**: BirdNion chỉ GET `coding_plan/remains` 1 region. CodexBar: HTML scrape → `__NEXT_DATA__` → `coding_plan/remains` → token-plan legacy fallback → China retry → **billing history** (`account/amount` 30d) → **subscription metadata** (expires/renews).
- **Parsing**: BirdNion mỗi model → 2 window (5h + Tuần) từ `current_*_remaining_percent`, lọc video (`:179-214`). CodexBar thêm `pointsBalance`→cost, billing cost, plan inference.
- **UI fields**: windows+accountLabel+planName. THIẾU: points balance, billing cost, subscription expiry/renewal.
- **Cosmetics**: displayName MATCH, logo ✓. tint BirdNion `#FF6700` — nghi dùng nhầm màu mimo Xiaomi (CodexBar minimax = rgb(254,96,60)). Region picker CÓ (io/com). Account switcher không.
- **Gaps**: (1) cân nhắc thêm cookie/web fetch path (scope lớn); (2) points balance + billing; (3) xác nhận brand tint.

## OpenRouter 🟡 PARTIAL
- **Auth**: Bearer `sk-or-...` từ config (`OpenRouterProvider.swift:36`) — MATCH (BirdNion thiếu env `OPENROUTER_API_KEY`, chỉ config).
- **Endpoints**: BirdNion chỉ GET `/api/v1/credits`. CodexBar thêm GET `/key` (limit/usage/usage_daily/weekly/monthly + rate-limit, headers HTTP-Referer/X-Title). → thiếu enrichment.
- **Parsing**: cả 2 `usedPct=usage/credits*100` + balance. BirdNion 1 window "Tín dụng" subtitle `$rem/$total`. CodexBar thêm `keyUsedPercent` window khi key có limit.
- **UI fields**: windows+creditsRemaining+accountLabel. THIẾU: key limit/daily/weekly/monthly, rate-limit.
- **Cosmetics**: displayName MATCH, tint `#6467F2` MATCH. dashboard link THIẾU (`openrouter.ai/settings/credits`).
- **Gaps**: (1) GET `/key` + per-key window; (2) env resolution; (3) dashboard link.

## DeepSeek 🟡 PARTIAL
- **Auth**: Bearer GET `/user/balance` (`DeepSeekProvider.swift:39-41`) — MATCH (thiếu env).
- **Endpoints**: chỉ `/user/balance`. CodexBar thêm `platform.deepseek.com/api/v0/usage/amount` + `/usage/cost` (today/month tokens+cost, per-model, daily, bounded join 2s).
- **Parsing**: BirdNion `total_balance` → 1 window "Số dư" usedPct=0, subtitle `$balance`, ¥/$ theo currency. CodexBar: ưu tiên USD-funded, Paid/Granted breakdown, usedPercent=100 khi balance≤0 (đỏ), usage summary.
- **UI fields**: windows+creditsRemaining+accountLabel. THIẾU: granted/paid breakdown, "add credits" khi balance=0, usage tokens/cost/daily.
- **Cosmetics**: displayName/logo/tint `#527DF0` MATCH. dashboard link THIẾU (`platform.deepseek.com/usage`).
- **Gaps**: (1) decode granted/topped_up vào subtitle; (2) cảnh báo balance≤0; (3) (optional) usage summary; (4) dashboard link.

## Zai 🟡 PARTIAL
- **Auth**: Bearer GET `/api/monitor/usage/quota/limit` (`ZaiProvider.swift:63-66`) — MATCH (thiếu env `Z_AI_QUOTA_URL`/`Z_AI_API_HOST`).
- **Endpoints**: chỉ quota/limit, 1 region (global/cn). CodexBar thêm `model-usage` API (hourly per-model chart, non-fatal).
- **Parsing**: BirdNion mỗi limit → 1 window theo `percentage`, label theo unit, reset từ `next_reset_time` ms (`:89-118`). CodexBar tinh hơn: `computedUsedPercent` (tránh 100% sai khi thiếu field) + tách primary/secondary/tertiary (TOKENS dài→primary, ngắn→session, TIME→MCP/Monthly).
- **UI fields**: windows+planName+accountLabel. THIẾU: model-usage chart, phân loại session/MCP window.
- **Cosmetics**: displayName "Z.ai / GLM" vs CodexBar "z.ai". logo/tint `#E85A6A` MATCH. Region picker CÓ (global/cn). dashboard link THIẾU.
- **Gaps**: (1) port `computedUsedPercent` (`ZaiUsageStats.swift:103-123`); (2) phân loại tokens/MCP/session; (3) (optional) model-usage chart; (4) dashboard link.

## Hapo (AIHub) — N/A
KHÔNG có ở CodexBar (custom BirdNion). Auth token config, endpoint từ env (`HAPO_BASE_URL`…). Flow: `budget/week` → `me` (email best-effort). 1 window "Tuần" usedPct=100−usage_percentage, subtitle `$rem/$weekly`, planLabel="Hapo AI Hub". Hoạt động tự đủ; không so sánh được.
