# Batch B — Cookie providers

CommandCode · MiMo · Alibaba · OpenCode · OpenCodeGo · Cursor
Kết: **0 full / 4 partial / 2 diverge.**

Chung: cookie-source UI (Auto/Manual/Off) **đạt parity đầy đủ cho cả 6** (`ProvidersPane.swift:1107-1157`). KHÔNG provider nào có dashboard/status link (CodexBar đều có).

---

## CommandCode 🟡 PARTIAL
- **Cookie**: domain `commandcode.ai`. BirdNion forward NGUYÊN cookie thô (`CommandCodeProvider.swift:54`, không lọc tên); CodexBar lọc đúng `__Host-/__Secure-better-auth.session_token` (`CommandCodeCookieHeader.swift:30-34`) + chấp nhận bare token. → PARTIAL.
- **Endpoints**: GIỐNG (`/internal/billing/credits` + `/subscriptions`, GET, cùng Origin/Referer/UA). CodexBar có grace 2s + flag enrichment-unavailable; BirdNion chỉ `try?`.
- **Parsing**: CodexBar tính 1 window `used/total` từ plan catalog, plan unknown → throw `unknownPlan` (`CommandCodeUsageFetcher.swift:62-65`). BirdNion: có plan total → 1 window "Tháng" %; không → window phẳng "Số dư/Credits/Premium" 0%/100% (`:152-177`). BỎ `opensourceMonthlyCredits`.
- **UI fields**: windows[Tháng|…], cost ✓, planName ✓. THIẾU: dòng tổng "Pro · $X of $Y · + $Z credits" (CodexBar gói vào loginMethod).
- **Cosmetics**: displayName "CommandCode" vs "Command Code". dashboard link THIẾU (`commandcode.ai/studio`, `/settings/billing`). cookie-source ✓.
- **Gaps**: (1) lọc cookie theo session-name (`:54`); (2) dashboard link; (3) surface unknown-plan thay vì window phẳng.

## MiMo 🟡 PARTIAL (gần FULL)
- **Cookie**: domain `platform.xiaomimimo.com`(+apex). Required `api-platform_serviceToken`+`userId`, optional `_ph/_slh` — MATCH (`MiMoProvider.swift:47-55`).
- **Endpoints**: GIỐNG (`balance` + `tokenPlan/detail` + `tokenPlan/usage`, GET concurrent). x-timeZone BirdNion `UTC+07:00` vs CodexBar `UTC+01:00` (cosmetic).
- **Parsing**: MATCH (balance, planCode.capitalized, monthUsage.items.first, periodEnd). Subtitle vi "Trả/Tặng".
- **UI fields**: windows[Số dư, Token Plan], planName ✓, cost ✓. Tương đương menu CodexBar.
- **Flow gap**: CodexBar có **MiMoLocalFetchStrategy** (cache local khi cookie fail) + CookieHeaderCache + multi-session retry; BirdNion không (nice-to-have).
- **Cosmetics**: displayName "MiMo" vs "Xiaomi MiMo". dashboard link THIẾU (`platform.xiaomimimo.com/#/console/balance`). cookie-source ✓.
- **Gaps**: (1) dashboard link; (2) (optional) displayName "Xiaomi MiMo"; (3) (optional) local cache fallback.

## Alibaba 🔴 DIVERGE/MISSING
- **Cookie**: domain `aliyun.com`. CSRF `login_aliyunid_csrf`/`csrf` → `x-csrf/x-xsrf-token` MATCH. sec_token: BirdNion CHỈ từ cookie (`AlibabaProvider.swift:202`); CodexBar 3 nguồn: dashboard HTML regex → `tool/user/info.json` → cookie (`AlibabaTokenPlanUsageFetcher.swift:278-330`). → PARTIAL (dễ fail khi cookie thiếu sec_token).
- **Endpoints/flow**: BirdNion = chỉ **Token Plan** (`bailian.console.aliyun.com` GetSubscriptionSummary, region cn-beijing). 🔴 **MISSING lớn**: CodexBar có **2 provider Alibaba**:
  - `alibabatokenplan` (BirdNion mirror cái này, id="alibaba").
  - `alibaba` = **Coding Plan** (5h/Weekly/Monthly windows, supportsOpus, region **intl/cn** endpoint khác hẳn, có API-token + web strategy). BirdNion KHÔNG có.
- **Parsing**: key-alias walk ngắn hơn (thiếu `usedCredit/creditLimit/validEndTime…` + subscriptionCount). Thiếu `expandedJSON` (JSON-trong-string) + fallback planName "TOKEN PLAN".
- **UI fields**: 1 window "Token Plan" %, planName ✓. THIẾU toàn bộ Coding Plan (3 windows).
- **Cosmetics**: displayName "Alibaba / Qwen" (CodexBar: "Alibaba Token Plan" + "Alibaba"). region UI THIẾU (Coding Plan có intl/cn). dashboard + `status.aliyun.com` THIẾU.
- **Gaps**: (1) thêm provider **Coding Plan** (5h/Weekly/Monthly + region intl/cn + API token); (2) mở rộng sec_token (HTML + user/info.json, `:202`); (3) key-alias + expandedJSON; (4) region picker + links.

## OpenCode 🟡 PARTIAL
- **Cookie**: domain `opencode.ai`, lọc `auth`/`__Host-auth` — MATCH (`OpenCodeProvider.swift:35`).
- **Endpoints**: GIỐNG (server RPC workspaces `def399…` → subscription `7abeeb…`, GET→POST fallback). CodexBar thêm: `workspaceID` override (settings/env), `isExplicitNullPayload` detection, parser candidate-walk sâu + `renewAt`. BirdNion parser nông (JSON 1 cấp + regex).
- **Parsing**: windows Rolling(5h)+Tuần — MATCH labels. THIẾU extraRateWindow **"Renews"** từ `renewAt` (`OpenCodeUsageSnapshot.swift:42-50`).
- **UI fields**: windows[Rolling, Tuần], subtitle "%". THIẾU "Renews".
- **Cosmetics**: displayName MATCH "OpenCode". dashboard link THIẾU. cookie-source ✓.
- **Gaps**: (1) parse `renewAt` → window "Renews"; (2) workspaceID override; (3) dashboard link.

## OpenCodeGo 🟡 PARTIAL
- **Cookie**: domain `opencode.ai`, `auth`/`__Host-auth` — MATCH.
- **Endpoints**: GIỐNG ý tưởng (workspace ID → `/workspace/<id>/go` + Zen balance RPC `c83b78a6…` ÷1e8). CodexBar dùng URLSession ephemeral + **RedirectGuardDelegate** (chặn cross-host redirect) + zen-balance delay + fallback; BirdNion đơn giản hơn, không redirect guard, không workspace override.
- **Parsing**: windows Rolling/Tuần/Tháng(optional) + Zen cost — MATCH cấu trúc. THIẾU extraRateWindow "Renews" (`OpenCodeGoUsageSnapshot.swift:91-99`).
- **UI fields**: windows[Rolling, Tuần, (Tháng)], cost ✓ (Zen). Gần khớp; THIẾU "Renews".
- **Flow gap**: CodexBar có **OpenCodeGoLocalUsageFetchStrategy**; BirdNion không.
- **Cosmetics**: displayName MATCH "OpenCode Go". dashboard link THIẾU. cookie-source ✓.
- **Gaps**: (1) parse `renewAt`; (2) (optional) local fallback + workspace override; (3) dashboard link.

## Cursor 🔴 DIVERGE/MISSING
- **Auth/Cookie**: BirdNion ưu tiên SQLite `state.vscdb` (`cursorAuth/accessToken` → JWT sub → `WorkosCursorSessionToken`) rồi cookie `cursor.com` (`CursorProvider.swift:39-45`). CodexBar ngược: manual → cache → browser cookies (đa tên `WorkosCursorSessionToken/wos-session/authjs/next-auth`, domains `cursor.com/www/cursor.sh/authenticator.cursor.sh`) → stored session → cuối mới SQLite (`CursorStatusProbe.swift:897-1023`). → DIVERGE (BirdNion 1 cookie name + 1 domain; thiếu cache/stored-session/multi-browser).
- **Endpoints/flow**: `/api/usage-summary` + `/api/auth/me` MATCH. 🔴 CodexBar còn `/api/usage?user=<sub>` cho **legacy request-based plans** (`fetchRequestUsage`, `:1225`); BirdNion THIẾU (model không có `limitType/isUnlimited/breakdown`).
- **Parsing**: Plan + On-demand windows + cost MATCH (cents→USD). THIẾU: legacy request usage; `personalUsed` trong team pool; resetDescription.
- **UI fields**: windows[Plan, On-demand], planName ✓, accountLabel=email ✓, cost ✓. CodexBar menu thêm **secondary "Auto" + tertiary "API" windows** (BirdNion gộp vào planPct), `cursorRequests` row legacy. THIẾU Auto/API lanes + legacy requests.
- **Cosmetics**: displayName MATCH "Cursor". dashboard link THIẾU (`cursor.com/dashboard?tab=usage`) + `status.cursor.com`. cookie-source ✓ NHƯNG `.off` không chặn SQLite path (`resolvedCookieHeader` chỉ gác browser cookie).
- **Gaps**: (1) legacy `/api/usage` request plan; (2) Auto/API lanes riêng; (3) mở rộng cookie names/domains + cache/stored-session; (4) `.off` chặn cả SQLite (`:39`); (5) dashboard + status link.
