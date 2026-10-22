# Tailor Khata — Sprint-wise Implementation Plan

> Companion to [feature-spec.md](feature-spec.md) (feature IDs like M-1, H-3, E-5) and [technical-design.md](technical-design.md) (section references like §5.6).

**Status:** Draft v0.1  **Scope:** v1.0 MVP  **Last updated:** 2026-10-22

---

## 1. Planning Assumptions

| Item | Assumption |
|---|---|
| Team | 1 full-time developer (Flutter). Design, QA and tailor feedback are part-time. Adjust sprint count if the team is larger |
| Sprint length | 2 weeks (10 working days) |
| Capacity | ~8 productive days per sprint per developer (2 days reserved for review, bug fixes, meetings, usability sessions) |
| Estimates | Ideal developer-days (**d**); 0.5 d minimum. Includes writing tests |
| Releases | Internal build at the end of every sprint; closed beta from Sprint 5; Play Store release after Sprint 7 |
| Order of work | Vertical slices, with the riskiest and most valuable piece (measurement history) first |

If the sprint total exceeds ~8 d, the lowest-priority task moves to the next sprint. P1 items are explicitly marked and are the first to be cut.

## 2. Roadmap Overview

| Sprint | Weeks | Theme | Demoable outcome |
|---|---|---|---|
| **S0** | 1–2 | Foundations | App boots, encrypted DB, Bangla/English, CI green |
| **S1** | 3–4 | Customers + Measurement capture | Add a customer, take and save measurements offline |
| **S2** | 5–6 | Measurement history (flagship) | Versions, timeline, compare, trend, edit-in-error |
| **S3** | 7–8 | Orders + Payments | Full order with advance/due, cutting slip PDF |
| **S4** | 9–10 | Deliveries + Reminders + Dashboard | Today/overdue lists, notifications, ready-message |
| **S5** | 11–12 | Eid-rush | Season setup, load calendar, safe-date suggestion, rush list |
| **S6** | 13–14 | Backup, security, hardening | Encrypted backup/restore, app lock, perf pass, beta |
| **S7** | 15–16 | Beta fixes + release | Play Store submission, onboarding, import, polish |

The technical design's 12-week plan (M0–M5) maps to S0–S6; S7 is a release buffer that is strongly recommended.

```
S0 ──► S1 ──► S2 ──► S3 ──► S4 ──► S5 ──► S6 ──► S7
 │      │      │      │      │      │      │      └─ release
 │      │      │      │      │      │      └─ beta (3–5 shops)
 │      │      │      │      │      └─ Eid-rush engine
 │      │      │      │      └─ reminders
 │      │      │      └─ money
 │      │      └─ history = product's core value
 │      └─ data entry
 └─ platform
```

## 3. Conventions

### 3.1 Task format

`ID | Task | Est | Depends on | Spec refs` followed by acceptance criteria for non-trivial tasks. IDs are `S<sprint>-<nn>`.

### 3.2 Definition of Ready (story enters a sprint)
- Acceptance criteria written; UI sketch exists for any new screen.
- Spec and design references identified; dependencies done.

### 3.3 Definition of Done (every task)
- Code merged to `main` via PR, reviewed (self-review checklist if solo).
- `flutter analyze` clean (strict lints); no new warnings.
- Unit tests for domain logic; DAO tests for data code; widget tests for non-trivial UI.
- Works in **both** `en` and `bn` locale (no hard-coded strings); no overflow at 1.3× text scale.
- Works fully **offline** (airplane mode).
- No customer data in logs.
- Verified on the low-end reference device (2 GB RAM Android).
- Schema changes include a migration and a migration test.

### 3.4 Branching and release
- Trunk-based: short-lived feature branches, squash merge to `main`, CI required.
- Tag `v0.<sprint>.0` at each sprint end; CI produces a signed internal APK.

### 3.5 Reference device and test data
- **Reference device:** a Redmi 9A-class phone (2 GB RAM, Android 10–12). Buy or borrow one in S0.
- **Seed generator** (built in S0): CLI/debug-menu action producing N customers, M orders, K measurement versions with realistic Bangla and English names. Used for perf tests (10k customers / 50k orders).

---

## Sprint 0 — Foundations (Weeks 1–2)

**Goal:** a skeleton that every later feature can plug into, with the hard platform decisions proven on a real cheap phone.

**Exit criteria:** app installs on the reference device, opens an encrypted DB, switches Bangla/English at runtime, CI is green on every PR, and the design system exists.

| ID | Task | Est | Depends | Refs |
|---|---|---|---|---|
| S0-01 | Create Flutter project; set package id, flavors (`dev`, `prod`), Dart strict lints, `.editorconfig`, README with setup | 0.5 d | — | TD §3.1 |
| S0-02 | CI (GitHub Actions): analyze, test, build debug APK, cache pub; coverage report; fail on lint | 1 d | S0-01 | TD §12 |
| S0-03 | Folder structure per TD §3.1; add Riverpod, go_router, freezed, json_serializable, Drift (+codegen setup, `build_runner` script) | 1 d | S0-01 | TD §2, §3 |
| S0-04 | **Encrypted Drift DB**: SQLCipher libs, key generation on first run, `flutter_secure_storage` storage, background-isolate open, wrong-key failure path | 1.5 d | S0-03 | TD §6, §11 |
| S0-05 | Core value objects with full unit tests: `Money` (poisha, lakh/crore grouping), `Length` (0.1 mm, inch fractions to 1/8, cm), `Fraction` parser, `Clock` abstraction | 1.5 d | S0-03 | TD §5.3, §5.4 |
| S0-06 | Localization: ARB for `en`/`bn`, `DigitFormatter` (Bangla digits at the presentation boundary), bundle Noto Sans Bengali subset, runtime locale switch persisted in `app_setting` | 1 d | S0-03 | TD §7.2 |
| S0-07 | Design system: theme (light/dark optional), type scale (Bangla-safe line heights), 48 dp touch targets, shared widgets (primary button, list tile, empty state, money text, status chip, section header) | 1.5 d | S0-06 | Spec §8 |
| S0-08 | App shell: router, bottom navigation (Home, Customers, Orders, Rush, More), placeholder screens | 0.5 d | S0-07 | Spec §7 |
| S0-09 | Schema v1 migration skeleton: `app_setting`, `audit_log`; migration test harness with fixture DBs | 0.5 d | S0-04 | TD §9 |
| S0-10 | Seed-data generator (debug menu) and perf-test harness stub | 1 d | S0-09 | TD §11 |
| S0-11 | Error/Result types, logging wrapper that redacts PII, global error boundary | 0.5 d | S0-03 | TD §6 |
| S0-12 | Obtain the reference device; run a "hello DB" smoke build; record baseline cold-start time | 0.5 d | S0-04 | TD §11 |

**Total:** ~11 d — slightly over capacity; S0-10 can slip into S1 if needed.

**Risks:** SQLCipher + Drift background isolate setup has gotchas. If it consumes more than 2 days, fall back to main-isolate open for v1 and revisit in S6.

---

## Sprint 1 — Customers and Measurement Capture (Weeks 3–4)

**Goal:** a tailor can add customers and take measurements quickly. This is the data-entry half of the flagship feature.

**Exit criteria:** create customer → pick garment → enter all fields with the custom keypad → save → reopen and see the numbers; all offline, in Bangla and English.

| ID | Task | Est | Depends | Refs |
|---|---|---|---|---|
| S1-01 | Schema + DAOs: `customer` (indexes, `name_norm`, `phone_digits`), soft delete, tests | 1 d | S0-09 | TD §4.2 |
| S1-02 | Normalizers: name normalization (NFC, Bangla composed forms), phone normalization (BD rules → E.164), with table-driven tests | 1 d | S0-05 | TD §7.1, §5.8 |
| S1-03 | Customer repository + use cases (create, update, soft-delete, duplicate-phone detection) | 1 d | S1-01, S1-02 | C-1, C-8 |
| S1-04 | Customer list + create/edit screens; empty state; swipe actions | 1.5 d | S1-03, S0-07 | C-1 |
| S1-05 | Search: FTS5 virtual table (name, phone), triggers to keep in sync, search bar with debounce; perf test at 10k customers (<200 ms) | 1.5 d | S1-01, S0-10 | C-2, S-1 |
| S1-06 | Schema + seed: `garment_type`, `measurement_field`, built-in templates for Panjabi, Shirt, Pant, Pajama, Blazer, Salwar Kameez, Blouse (en + bn labels, soft ranges) | 1 d | S0-09 | M-1, Spec §5.2.5 |
| S1-07 | **Fast measurement keypad widget**: digits, ½ ¼ ⅛ ¾ keys, decimal, next/previous field, auto-advance; unit toggle; large targets; widget tests | 2 d | S0-05, S0-07 | M-2, M-3 |
| S1-08 | Measurement entry screen driven by a template: field list, per-field validation (soft range warning, never block), note field, taken-on date (default today) | 1.5 d | S1-06, S1-07 | M-1, M-5, §4.4 |
| S1-09 | Schema + DAO + repository: `measurement_set` / `measurement_value` with version assignment in one transaction (no history UI yet) | 1 d | S1-06 | H-1, TD §5.1 |
| S1-10 | **Append-only DB triggers** on measurement tables + tests proving UPDATE/DELETE abort | 0.5 d | S1-09 | TD §5.1 |
| S1-11 | Customer profile screen skeleton: header, tabs (Overview, Measurements, Orders, Payments), measurement tab lists latest per garment | 1 d | S1-04, S1-09 | C-3 |

**Total:** ~12.5 d — over capacity. **Cut/slip candidates (in order):** S1-05 FTS tuning (use `LIKE` first, FTS in S2), S1-11 polish.

**Acceptance criteria — key tasks**
- *S1-07:* entering `38 ½` yields 9779 stored units; `⅛` rounds correctly; backspace and field jump work with one hand; no on-screen keyboard overlap on a 5" screen.
- *S1-09/10:* two concurrent saves for the same (customer, garment) never produce duplicate versions (unique constraint + retry); any attempt to update a value row throws.
- *S1-02:* `01712-345678`, `+8801712345678`, `8801712345678` all normalize identically.

**Demo:** add "Rahim Uddin", take Panjabi measurements, kill the app, reopen, numbers are intact.

---

## Sprint 2 — Measurement History (Weeks 5–6)

**Goal:** deliver the feature the product is built around: versioned history, compare, and trend.

**Exit criteria:** a customer with 4 versions of Panjabi measurements shows a timeline, compares any two versions with highlighted deltas, charts a field over time, and a mistaken version can be flagged without being deleted.

| ID | Task | Est | Depends | Refs |
|---|---|---|---|---|
| S2-01 | "Edit" = new version: prefill from latest, change detection (no change → no new version), `supersedes_id`, "latest" query by `taken_on` then `version` | 1 d | S1-09 | H-1, H-5, TD §5.1 |
| S2-02 | Backdated entry support for paper-book import (taken_on in the past does not hijack "latest") | 0.5 d | S2-01 | H-9 |
| S2-03 | **Diff engine** (pure Dart): per-field deltas, added/removed/changed, cross-garment shared keys; exhaustive unit tests | 1 d | S0-05 | H-3, TD §5.2 |
| S2-04 | History timeline screen: per garment, version cards (date, measured-by, delta summary vs. previous, linked order placeholder), "Include errors" toggle | 1.5 d | S2-01 | H-2 |
| S2-05 | **Compare screen**: pick any two versions, side-by-side table, changed rows highlighted with +/- delta, filter "changed only" | 1.5 d | S2-03, S2-04 | H-3 |
| S2-06 | Change-confirmation at save: warn when a field changes by more than threshold (default 1.5 in, configurable per field) | 0.5 d | S2-03 | §4.4 |
| S2-07 | "Entered in error" flow: `status='error'` set, hidden from latest/compare/trend, reversible, audit-logged | 1 d | S2-04 | H-1, B-7 |
| S2-08 | Trend chart (`fl_chart`): single field over time, tap point for value/date, unit-aware (P1 — cut if behind) | 1.5 d | S2-04 | H-4 |
| S2-09 | "Fit outcome" marking: confirmed / needed alteration on a version; best-fit indicator on the latest card (P1) | 1 d | S2-04 | H-6 |
| S2-10 | Measurement history PDF/image export for sharing (P1) | 1 d | S2-04 | H-10 |
| S2-11 | Perf and correctness: history with 50 versions per garment renders under 100 ms; seed test | 0.5 d | S2-04, S0-10 | TD §11 |
| S2-12 | Usability session #1 with 2–3 real tailors on the capture + history flow (paper prototype/build); record findings | 0.5 d | S2-05 | Spec §11 |

**Total:** ~11.5 d. **Cut candidates:** S2-10, S2-09, then S2-08.

**Acceptance criteria — key tasks**
- *S2-01:* saving unchanged values creates no row; changing one field creates v(n+1) with `supersedes_id = v(n)`; v(n) values unchanged byte-for-byte.
- *S2-05:* chest 38 → 40 shows "38 → 40 (+2)"; fields only in one version show as added/removed.
- *S2-07:* after flagging v3 as error, "latest" returns v2 and compare/trend omit v3; unflagging restores.

**Demo:** the headline moment — pull up a customer, scroll back through years of Panjabi measurements, compare the oldest to the newest.

---

## Sprint 3 — Orders and Payments (Weeks 7–8)

**Goal:** complete order capture with money, linked to the exact measurement snapshot.

**Exit criteria:** Flow A (returning customer, new order) completes in under 60 seconds on the reference device; due is always correct; a cutting slip can be shared as PDF.

| ID | Task | Est | Depends | Refs |
|---|---|---|---|---|
| S3-01 | Schema + DAOs: `order`, `order_item`, `payment`, `attachment`, `worker` (table only), `v_order_money` view; migration + tests; sequential order number allocation | 1.5 d | S2-01 | TD §4.2–4.3 |
| S3-02 | Money domain use cases: total, paid, due, credit (overpayment); property tests (due = total − Σ payments for random sequences) | 1 d | S0-05, S3-01 | P-3 |
| S3-03 | Order repository + `CreateOrder` use case (transaction: order, items, snapshot link, advance payment); draft autosave | 1.5 d | S3-01, S3-02 | O-1, O-4, P-1 |
| S3-04 | **New-order wizard**: garment → measurements ("No change" / "Edit" with last values and date) → style details → price & advance → delivery date; resume from draft | 2.5 d | S3-03, S2-01 | O-1, O-2, H-5 |
| S3-05 | Style options per garment (collar, pocket, cuff, buttons, lining, embroidery) stored in `style_json`; configurable list in settings | 1 d | S3-04 | O-2 |
| S3-06 | Photo attachments: capture/pick, compress ≤1280 px / ~300 KB, thumbnails, app-private storage | 1 d | S3-04 | O-3, TD §11 |
| S3-07 | Order detail screen: items, status chips, payments list, due banner (red/green), change log | 1.5 d | S3-03 | O-11, P-3 |
| S3-08 | Item status pipeline: transitions (forward + one-step back), `status_changed_at`, order status roll-up in the same transaction, bulk status update | 1 d | S3-03 | O-7, O-8 |
| S3-09 | Payments UI: add payment (method, date, note), refund/adjustment (P1) | 1 d | S3-07 | P-1, P-2, P-7 |
| S3-10 | Dues list ("who owes me"): per-customer sum, sorted by amount/age; customer-level due on profile | 1 d | S3-02 | P-5 |
| S3-11 | Duplicate order ("same as last Eid"), cancel with reason + advance handling | 1 d | S3-07 | O-12, O-13 |
| S3-12 | **Cutting slip PDF** (items, measurements, style notes, photos thumbnails, delivery date, big order number) + share | 1.5 d | S3-07 | M-9 |
| S3-13 | Integration test: Flow A scripted with a stopwatch assertion; Flow C using order snapshots | 0.5 d | S3-04 | Spec §6 |

**Total:** ~16 d — **well over capacity; split across S3 and a spill into S4.** Recommended split: S3 keeps S3-01…S3-04, S3-07, S3-08, S3-10, S3-13 (~11 d, still tight; push S3-04's photo piece and S3-05 to S4). Move S3-05, S3-06, S3-09 refunds, S3-11, S3-12 to the front of S4 and shift S4's lower-priority items accordingly. Treat S3 as the hardest sprint to scope.

**Acceptance criteria — key tasks**
- *S3-04:* "No change" links the existing measurement set to the item without creating a new version; "Edit" creates v(n+1) and links that one.
- *S3-02/S3-07:* adding a payment updates due on the order card, dues list, and dashboard without a manual refresh (stream-driven).
- *S3-08:* marking the last item Delivered flips order status to Delivered; an item set back one step reverts the roll-up.
- *S3-01:* two orders created back to back never share a number.

---

## Sprint 4 — Deliveries, Reminders, Dashboard (Weeks 9–10)

**Goal:** the tailor knows what must go out today, gets reminded, and can message the customer in one tap. Includes the spillover from S3.

**Exit criteria:** Flow D works end to end; reminders fire and survive a reboot; the Home dashboard answers "what do I need to do today?" at a glance.

| ID | Task | Est | Depends | Refs |
|---|---|---|---|---|
| S4-01 | *(Spill from S3)* Style options, photo attachments, duplicate/cancel, cutting slip PDF, refunds (see S3-05, 06, 09, 11, 12) | 5 d | S3-* | — |
| S4-02 | Deliveries screen: Today / Tomorrow / This week / Overdue tabs, grouped by date, indexed query, keyset pagination | 1.5 d | S3-03 | D-1 |
| S4-03 | **Deliver guard**: `DeliverOrder` use case enforces explicit confirm when due > 0, with "Collect & deliver" shortcut | 1 d | S3-08, S3-09 | P-4 |
| S4-04 | Mark Ready → "Send message" action: message templates (editable), BD phone normalization, `sms:` and `wa.me` deep links, graceful fallback if no phone | 1 d | S1-02 | D-3, TD §5.8 |
| S4-05 | `ReminderScheduler`: grouped notifications (evening-before, morning-of, overdue digest), reschedule on order changes, rebuild on app start and boot, deep-link payload | 2 d | S3-03 | D-2, D-4, TD §5.7 |
| S4-06 | Notification permissions UX (Android 13+), battery-optimization guidance screen, settings for reminder times | 0.5 d | S4-05 | R1 |
| S4-07 | Home dashboard: today's deliveries, overdue count, total outstanding due, orders received today, quick actions; aggregated queries, debounced streams | 1.5 d | S4-02, S3-10 | S-3 |
| S4-08 | Reschedule delivery with reason (P1); uncollected-garments list (P1) | 1 d | S4-02 | D-5, D-6 |
| S4-09 | Filters and global search extended to orders (status, dates, due>0, garment) | 1 d | S4-02, S1-05 | S-1, S-2 |
| S4-10 | Integration test Flow D; reminders test using fake clock + scheduler spy | 0.5 d | S4-05 | — |

**Total:** ~15 d — **over capacity.** Plan to complete S4-01 spill first (it blocks the order feature set), then S4-02, S4-03, S4-05, S4-07; P1 items (S4-08) slide to S6/S7 buffer.

**Acceptance criteria — key tasks**
- *S4-05:* editing a delivery date replaces the old notifications; notifications for 5 orders on the same day collapse to one "5 deliveries tomorrow"; after device reboot they are rebuilt on next app open or boot.
- *S4-03:* no code path other than `DeliverOrder` can set an item to Delivered with due > 0 without the confirm flag (unit-tested).

---

## Sprint 5 — Eid-Rush (Weeks 11–12)

**Goal:** the seasonal differentiator: capacity vs. commitments, with a safe-date suggestion at order time.

**Exit criteria:** with a configured Eid season, the load calendar shows green/amber/red days, new orders get a suggested earliest safe date, and the rush list is usable at a glance.

| ID | Task | Est | Depends | Refs |
|---|---|---|---|---|
| S5-01 | Schema + DAOs: `season`; `work_units` per garment type (editable weights); closed dates and working-day mask | 1 d | S3-01 | E-1, E-4 |
| S5-02 | Season setup UI: type (Eid-ul-Fitr/Adha/Puja/Pohela Boishakh/wedding/custom), target date, daily capacity, working days, closed dates; presets | 1.5 d | S5-01 | E-1, E-4 |
| S5-03 | **Capacity engine** (pure Dart): load per day, utilisation/colour, EDF feasibility, `earliestSafeDate`, `lastDateToAccept`; single `CapacityLane` interface for v1.1 extension | 2 d | S5-01 | E-3, E-5, E-6, TD §5.6 |
| S5-04 | Engine tests: table-driven scenarios + **property tests** (a date returned as safe never causes overbooking; monotonic in capacity); perf with 60-day horizon and 2,000 items | 1 d | S5-03 | TD §12 |
| S5-05 | Countdown board: days left, orders by status, garments not yet cut | 1 d | S5-03 | E-2 |
| S5-06 | **Load calendar**: day cells with committed/capacity and colour; tap a day to see its orders | 1.5 d | S5-03 | E-3 |
| S5-07 | Safe-date suggestion in the order wizard: pre-fills the delivery date, shows "Earliest safe: 14 Mar", override on a red day needs confirm and tags order `overbooked` | 1 d | S5-03, S3-04 | E-5 |
| S5-08 | Batch lists: group unfinished items by garment type and stage ("37 Panjabi, 12 Pant to cut"), one-tap bulk status | 1 d | S3-08 | E-8 |
| S5-09 | Compact rush list: one line per order, large text, sorted by delivery date, status swipe | 1 d | S4-02 | E-11 |
| S5-10 | Production board (kanban) by status (P1); at-risk list (P1) | 2 d | S5-03 | E-7, E-9 |
| S5-11 | "Last date to accept" banner and rush-day cash summary (P1) | 0.5 d | S5-03 | E-6, E-10 |
| S5-12 | Usability session #2 with tailors on rush features using a seeded 300-order season | 0.5 d | S5-09 | — |

**Total:** ~14 d with P1s; ~10 d for P0 only (S5-01…S5-09, S5-12). **Plan P0 only; P1 items go to the backlog for v1.1.**

**Acceptance criteria — key tasks**
- *S5-03:* with capacity 10 units/day and 5 days left, adding 60 units due on day 5 yields no safe date for the last 10 units; the earliest safe date for a new 1-unit order is the first day where cumulative capacity ≥ cumulative demand including it.
- *S5-07:* picking a red day shows a clear warning and requires one extra tap.
- *S5-06:* calendar renders 60 days with 2,000 items in under 100 ms.

---

## Sprint 6 — Backup, Security, Hardening (Weeks 13–14)

**Goal:** make data loss nearly impossible and ship a build real shops can trust. Start the closed beta.

**Exit criteria:** backup → wipe → restore round-trip passes in CI and on a physical device; app lock works; performance budgets met on the reference device; 3–5 beta shops installed.

| ID | Task | Est | Depends | Refs |
|---|---|---|---|---|
| S6-01 | Backup package builder: `VACUUM INTO` snapshot + media + manifest (schemaVersion, checksums), zip, AES-256-GCM encryption with Argon2id-derived key from a passphrase | 2 d | S3-06 | B-2, TD §8, §6 |
| S6-02 | Google Drive `appDataFolder` upload/download + Google sign-in; local-file export fallback via share sheet (for restore from any storage) | 2 d | S6-01 | B-2, R2 |
| S6-03 | Scheduled backup (WorkManager: daily, Wi-Fi), "Last backed up" badge on Home with 7-day warning | 1 d | S6-02 | B-2 |
| S6-04 | **Restore**: download, decrypt, verify checksums and schemaVersion, atomic DB swap with `pre_restore` copy, forward migrations; clear error states | 2 d | S6-01 | B-3, TD §8 |
| S6-05 | CI restore round-trip test (seed → backup → wipe → restore → assert equal) + corrupted/wrong-passphrase cases | 1 d | S6-04 | TD §8 |
| S6-06 | Soft-delete recovery: recently-deleted screen, 30-day purge job | 1 d | S1-01, S3-01 | B-8 |
| S6-07 | App lock: PIN setup, hash in secure storage, biometrics, auto-lock on background timeout | 1.5 d | S0-04 | TD §6 |
| S6-08 | Performance pass on reference device: cold start <2 s, 10k-customer search <200 ms, frame times; fix hot spots; add `EXPLAIN QUERY PLAN` assertions for hot queries | 1.5 d | all | TD §11 |
| S6-09 | Accessibility and localization audit: text scale 1.3×, contrast, missing `bn` strings, Bangla digits everywhere | 1 d | all | Spec §8 |
| S6-10 | CSV/Excel export (customers, orders, payments, measurements) (P1) | 1 d | S3-01 | B-4 |
| S6-11 | Beta distribution: Play Console internal testing track (or direct signed APK), crash reporting (opt-in, PII-scrubbed), feedback form | 1 d | — | — |

**Total:** ~15 d — **over capacity.** Priority: S6-01, 02 (or local-file fallback only), 04, 05, 07, 08 are non-negotiable. S6-10 and part of S6-09 can move to S7.

**Acceptance criteria — key tasks**
- *S6-04:* a backup made on device A restores on device B with all customers, every measurement version, payments and photos; wrong passphrase gives a clear error without touching the current DB.
- *S6-07:* backgrounding the app for longer than the timeout requires PIN/biometric; forgetting the PIN has a documented reset path that does not destroy data (re-verify via device credential).

---

## Sprint 7 — Beta Fixes and Release (Weeks 15–16)

**Goal:** turn beta feedback into fixes, finish onboarding and migration from paper, and ship to the Play Store.

**Exit criteria:** zero known data-loss or crash bugs; store listing approved; first public release live.

| ID | Task | Est | Depends | Refs |
|---|---|---|---|---|
| S7-01 | Beta bug triage and fixes (reserve ≥ 3 d; scope set by findings) | 3 d | beta | — |
| S7-02 | **Onboarding**: language choice, shop profile (name, logo, phone), pick garments, capacity wizard for rush, optional backup setup | 1.5 d | S5-02 | Spec §5.9 |
| S7-03 | **Paper-book import helper**: fast "backfill past customer" flow (name + phone + backdated measurements in one screen) | 1.5 d | S2-02 | H-9 |
| S7-04 | Settings completeness: units, currency, order prefix, message templates, notification times, garment/field templates editor (M-4) | 2 d | S1-06 | M-4, Spec §5.9 |
| S7-05 | Template editor: add/remove/reorder fields per garment, archive fields without orphaning history | 1 d | S7-04 | M-4, TD §5.1 |
| S7-06 | Play Store assets: icon, screenshots in Bangla and English, listing text, privacy policy, data-safety form; release signing, `.aab` pipeline | 1.5 d | — | — |
| S7-07 | Release checklist run: migrations from every previous internal build, clean-install and upgrade tests, restore from an S6 backup | 1 d | all | TD §9 |
| S7-08 | Ship v1.0; monitor crash-free sessions and backup success for 1 week | 0.5 d | S7-06 | Spec §11 |

**Total:** ~12 d. Buffer comes from S7-01; if beta is quiet, pull v1.1 P1 items forward (see §5).

---

## 4. Cross-Sprint Workstreams

| Workstream | Cadence | Notes |
|---|---|---|
| **Usability sessions with real tailors** | S2, S5, S6 beta | Observe real use on a cheap phone; 3 participants is enough to find the big problems. Record time to complete Flow A |
| **Bangla quality review** | Every sprint (30 min) | Native speaker reviews new strings; keep a glossary (naap, khata, advance, due, karigor) |
| **Performance regression guard** | CI from S1 | Benchmarks on seed data; fail if search >300 ms or cold start regresses >20% |
| **Migration discipline** | Every schema change | Fixture DB per version, migration test required |
| **Docs** | Continuous | Update the spec when a decision changes; keep the decision log in the technical design |

## 5. Backlog Beyond v1.0 (candidates)

**v1.1 — Run the rush:** workers and assignment (O-9, §5.8), per-worker capacity lanes, production board (E-7), at-risk list (E-9), family profiles (C-5), receipts (P-6), daily cash summary (P-8), reports (S-4), tags (C-6), audit-trail UI (B-7).

**v1.2 — Run the shop:** multi-device sync (B-5; TD §10), voice measurement input (M-7), customer-fabric tracking (O-15), iOS release, season report (E-12), Bluetooth thermal printing.

## 6. Risks and Mitigations (delivery)

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| S3 and S4 are overloaded (flagged above) | High | Schedule slip | Treat as ~3 sprints of work; P1 items pre-identified to cut; consider a second developer from S3 |
| SQLCipher/Drift isolate issues | Medium | 2–3 day loss in S0 | Time-box; fallback to main-isolate open |
| Notification reliability on OEM-skinned Android | High | Missed reminders erode trust | Dashboard is source of truth; battery-optimization guidance (S4-06); test on 2+ OEM devices |
| Real tailors reject the keypad or flow | Medium | Core UX rework | Usability session #1 in S2, early enough to adjust before orders are built on top |
| Capacity model feels wrong in practice | Medium | Eid feature distrusted | Suggestions are overridable; gather real-season data in beta; weights editable |
| Google Drive sign-in friction | Medium | Users skip backup | Local-file export fallback (S6-02); persistent backup badge |
| Scope creep from beta feedback | High | v1 never ships | Triage rule: only data-loss, crash, and Flow A/C/D blockers fix in S7; rest to backlog |
| Single-developer bus factor | Medium | Stalled project | Keep docs current; CI-enforced tests; small PRs |

## 7. Milestone Checklist (go / no-go)

- [ ] **End S2:** a tailor can see and compare years of measurements (the "worth the app" test) — demo to a real tailor.
- [ ] **End S3/S4:** Flow A < 60 s on reference device; due math verified by property tests.
- [ ] **End S5:** safe-date suggestion matches hand calculation on 3 seeded scenarios.
- [ ] **End S6:** restore round-trip green in CI and verified manually on two devices; performance budgets met.
- [ ] **End S7:** crash-free sessions ≥ 99%, no open data-loss bugs, store listing live.
