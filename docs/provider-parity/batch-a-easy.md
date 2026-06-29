# Batch A — EASY/simple providers

ElevenLabs · Deepgram · Groq · Copilot · Kilo
Kết: **0 full / 3 partial / 2 diverge.**

---

## ElevenLabs 🟡 PARTIAL
- **Auth**: API key header `xi-api-key` — MATCH (`ElevenLabsProvider.swift:27` ↔ `ElevenLabsUsageFetcher.swift:196`).
- **Endpoints**: cả 2 GET `/v1/user/subscription`. CodexBar có env override `ELEVENLABS_API_URL`; BirdNion hardcode → PARTIAL (không quan trọng GUI).
- **Parsing/data**: BirdNion lấy `character_count/limit`, `voice_slots_used/limit`, `tier`, reset. CodexBar lấy THÊM `professional_voice_slots_used/limit`, `current_overage`, `status`.
- **UI fields**: windows=[Credits, Voice slots], planName=tier. THIẾU: window "Professional voices"; suffix `status` trên tier (CodexBar: `Pro · canceled`).
- **Cosmetics**: displayName ✓, logo ✓ (tint mono). dashboard link THIẾU (`elevenlabs.io/app/subscription`).
- **Gaps**: (1) thêm window Professional voices (`ElevenLabsProvider.swift:60-64`); (2) tier kèm `status`; (3) dashboard link.

## Deepgram 🔴 DIVERGE
- **Auth**: `Authorization: Token <key>` — MATCH (`DeepgramProvider.swift:72`).
- **Endpoints/flow**: BirdNion list projects → lấy **project ĐẦU TIÊN** → GET `/usage/breakdown` 30d (`DeepgramProvider.swift:30,38-45`). CodexBar **lặp TẤT CẢ projects + aggregate** (`DeepgramUsageFetcher.swift:343-351`, `aggregate()` :242) + field override "Project ID". → DIVERGE: sai số usage khi key nhiều project.
- **Parsing/data**: BirdNion chỉ `requests` + `hours`. CodexBar thêm `total_hours` (billable), `agent_hours`, `tokens_in/out`, `tts_characters` (`:194-228`).
- **UI fields**: windows=[Requests(30d), Audio(30d)] usedPct=0 info-only, planName="Project: <name>". THIẾU: billable/agent hours, tokens, TTS chars, nhãn "N projects".
- **Cosmetics**: tint BirdNion `#13EF93` vs CodexBar branding `#6467F2` (tím) — LỆCH. Settings: thiếu field "Project ID".
- **Gaps**: (1) aggregate toàn bộ project (`DeepgramProvider.swift:30`); (2) Project ID override; (3) thêm metrics.

## Groq 🟡 PARTIAL
- **Auth**: `Bearer <key>` — MATCH.
- **Endpoints**: Prometheus `api/v1/query`. BirdNion 3 metric (requests, tokens_in, tokens_out, `GroqProvider.swift:25-27`); CodexBar 4 — **thêm `prompt_cache_hits:rate5m`** (`GroqUsageFetcher.swift:167-171`). URL BirdNion hardcode; CodexBar build + env override.
- **Parsing**: scalar Prometheus giống. BirdNion gộp req/min + tok/min vào **1 window** 1 subtitle (`:33-37`); CodexBar tách primary(req/min)/secondary(tok/min)/tertiary(cache/min) — 2-3 window riêng.
- **UI fields**: windows=[1 window "Hoạt động (5m)"], planName="Prometheus metrics". THIẾU: window tokens/min + cache hits/min riêng.
- **Cosmetics**: tint `#F15A29` ≈ CodexBar `#F56844`. dashboard link THIẾU (`console.groq.com/dashboard/metrics`).
- **Gaps**: (1) thêm query cache-hits; (2) tách 2-3 window; (3) dashboard link.

## Copilot 🔴 DIVERGE
- **Auth**: GitHub token `Authorization: token` — MATCH cơ bản. CodexBar còn có **OAuth Device Flow login** + multi-account; BirdNion chỉ paste token. → PARTIAL auth.
- **Endpoints/flow**: cả 2 GET `/copilot_internal/user` cùng header editor-version. CodexBar hỗ trợ **enterprise host** `api.<host>` (`CopilotUsageFetcher.swift:31-40`); BirdNion hardcode `api.github.com`. CodexBar có **Budget web extras** (cookie GitHub → scrape `/settings/billing/budgets`) → windows "Budget - ..."; BirdNion KHÔNG.
- **Parsing**: premium_interactions + chat, skip unlimited, usedPct=100−remaining — khớp logic. accountLabel: BirdNion = token prefix; CodexBar resolve **GitHub username thật** (`fetchGitHubUsername`).
- **UI fields**: windows=[Premium, Chat], planName, reset ✓. THIẾU: budget windows, overQuota desc, enterprise, username.
- **Cosmetics**: displayName "GitHub Copilot" vs CodexBar "Copilot" — LỆCH. tint mono vs CodexBar tím `#A855F7` — LỆCH. Settings thiếu budget toggle/cookie picker/enterprise host/Add Account.
- **Gaps**: (1) displayName "Copilot"; (2) username thật; (3) budget extras + enterprise + device flow; (4) tint.

## Kilo 🟡 PARTIAL
- **Auth**: `Bearer <key>` từ config. CodexBar thêm **CLI auth.json fallback** (`~/.local/share/kilo/auth.json`) + source picker auto/api/cli. → PARTIAL.
- **Endpoints**: tRPC batch `user.getCreditBlocks,kiloPass.getState,user.getAutoTopUpPaymentMethod` — MATCH (`KiloProvider.swift:43-47`). CodexBar thêm **org scope** (`X-KILOCODE-ORGANIZATIONID` + multi-org loop); BirdNion personal-only (comment `:10`).
- **Parsing**: credit blocks (mUsd÷1e6), pass, tier→plan name — khớp ~1:1. BirdNion BỎ `autoTopUpEnabled/method` (CodexBar nối vào loginMethod) + fallback parse pass.
- **UI fields**: windows=[Credits, Kilo Pass], creditsRemaining ✓, planName ✓, cost ✓ (BirdNion hơn — CodexBar set providerCost=nil). THIẾU: auto-top-up status; org windows.
- **Cosmetics**: displayName "Kilo Code" vs "Kilo" — LỆCH. tint `#7C5CFF` (tím) vs CodexBar `#F27027` (cam) — LỆCH mạnh. Settings thiếu source picker + Organizations.
- **Gaps**: (1) displayName "Kilo"; (2) CLI source fallback; (3) org scope; (4) auto-top-up; (5) tint.
