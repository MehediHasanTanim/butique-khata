# Tailor Khata — Technical Design

> Companion to [feature-spec.md](feature-spec.md). Feature IDs (M-1, H-3, E-5, ...) refer to that document.

**Status:** Draft v0.1  **Scope:** v1.0 (MVP) in detail, v1.1/v1.2 as extension points  **Last updated:** 2026-10-22

---

## 1. Goals and Constraints

| Constraint | Consequence for design |
|---|---|
| Must work with no internet | Local database is the source of truth; no backend in v1 |
| Low-end Android (2 GB RAM) | Native-compiled UI, lazy lists, small images, indexed queries, no heavy startup work |
| Measurement history must never be lost | Append-only versioning, soft deletes, encrypted backup with restore tested in CI |
| Bangla + English | ICU-based localization, Bangla digit formatting, Unicode-aware search |
| One developer / small team | One codebase, few moving parts, boring technology |
| Money correctness | Integer amounts, derived (not stored) due, immutable payments |

## 2. Technology Choices

| Layer | Choice | Why | Alternative considered |
|---|---|---|---|
| UI framework | **Flutter** (Dart 3) | One codebase for Android and iOS, consistent rendering on cheap devices, good Bangla text shaping, large widget ecosystem | React Native (more JS-ecosystem libs, but heavier bridge on low-end devices) |
| State management | **Riverpod** | Compile-safe, testable, works well with streams from the DB | Bloc (more boilerplate) |
| Local DB | **SQLite via Drift** | Typed queries, migrations, reactive streams, relational data fits the domain | Isar/Hive (weaker for relational queries and migrations) |
| Encryption | **SQLCipher** (`sqlcipher_flutter_libs`) | Encryption at rest, transparent to Drift | App-level file encryption (clumsier) |
| Navigation | `go_router` | Declarative, deep-link friendly (notifications open an order) | Navigator 2 by hand |
| Notifications | `flutter_local_notifications` + `timezone` | Scheduled, offline, no server | FCM (needs backend, unnecessary) |
| Images | `image_picker` + `flutter_image_compress` | Compress at capture | — |
| PDF / share | `pdf` + `printing` + `share_plus` | Cutting slips and receipts as PDF/image | — |
| Backup | Google Drive `appDataFolder` (Android), iCloud container (iOS) | User's own storage, no server cost, hidden from normal Drive UI | Own cloud (cost, privacy burden) |
| Secrets | `flutter_secure_storage` (Keystore / Keychain) | DB key and app-lock PIN hash | — |
| Charts | `fl_chart` | Trend view (H-4), reports | — |
| Codegen | `freezed`, `json_serializable`, Drift codegen | Immutable models, safe serialization | — |
| Testing | `flutter_test`, `integration_test`, `mocktail`, Drift in-memory DB | — | — |
| CI | GitHub Actions: analyze, test, build APK/AAB | — | — |

## 3. Architecture

Layered, feature-first, with unidirectional data flow.

```
┌──────────────────────────────────────────────┐
│ Presentation (Flutter widgets, Riverpod)     │
│  screens/ widgets/ controllers (Notifiers)   │
├──────────────────────────────────────────────┤
│ Domain (pure Dart, no Flutter/Drift imports) │
│  entities, value objects, use cases,         │
│  capacity engine, measurement diff engine    │
├──────────────────────────────────────────────┤
│ Data                                         │
│  repositories (interfaces in domain)         │
│  Drift DAOs, mappers, file store, backup     │
├──────────────────────────────────────────────┤
│ Platform services                            │
│  notifications, secure storage, drive/iCloud,│
│  share, contacts, biometrics                 │
└──────────────────────────────────────────────┘
```

### 3.1 Project structure

```
lib/
  main.dart
  app/                      # app shell, router, theme, l10n wiring
  core/
    db/                     # Drift database, migrations, encryption
    money/                  # Money value object
    units/                  # Length value object (inch/cm), fractions
    time/                   # Clock abstraction, date helpers
    l10n/                   # ARB files (en, bn), digit formatter
    errors/                 # Result/Failure types
    services/               # notifications, secure_storage, share, backup
  features/
    customers/    {data, domain, presentation}
    measurements/ {data, domain, presentation}   # flagship
    orders/       {data, domain, presentation}
    payments/     {data, domain, presentation}
    deliveries/   {data, domain, presentation}
    rush/         {data, domain, presentation}
    workers/      {data, domain, presentation}   # v1.1
    settings/     {data, domain, presentation}
    backup/       {data, domain, presentation}
test/
integration_test/
```

Rules: `domain/` imports nothing from Flutter, Drift, or platform packages. Features talk to each other only through repository interfaces or domain events, never through each other's DAOs.

### 3.2 Reactive data flow

DAOs expose `Stream<T>` (Drift `watch`). Riverpod `StreamProvider`s feed the UI, so a payment recorded on one screen updates the dues list and dashboard immediately with no manual refresh.

## 4. Data Design

### 4.1 Conventions
- **IDs:** UUIDv7 stored as TEXT (time-ordered, safe for future multi-device sync, no collisions between devices).
- **Timestamps:** UTC epoch milliseconds (`INTEGER`). Display in device timezone. *Calendar dates* (delivery date, taken_on) are stored as `TEXT` `YYYY-MM-DD` to avoid timezone drift.
- **Money:** `INTEGER` in poisha (1 BDT = 100). Never floats.
- **Lengths:** stored as `INTEGER` in tenths of a millimetre (0.1 mm; 1 inch = 254 units). Whole inches, cm and 0.1 mm values are exact; fractions such as 1/8 inch (31.75 units) are stored to the nearest unit (error under 0.01 mm), and display rounding to 1/8 inch recovers them exactly. There are no floats to compare. Display converts to inch fractions (to nearest 1/8 by default) or cm. Round-trip: a value typed as 38½" is stored as 9779 (0.1 mm) and shown back as 38½".
- **Soft delete:** `deleted_at INTEGER NULL` on customers, orders, workers. Purged after 30 days (B-8).
- **Sync-ready columns** on mutable tables: `created_at`, `updated_at`, `device_id`, `rev` (integer). Unused in v1 but cheap now and painful to retrofit.

### 4.2 Schema

```sql
-- Customers
CREATE TABLE customer (
  id            TEXT PRIMARY KEY,
  name          TEXT NOT NULL,
  name_norm     TEXT NOT NULL,           -- normalized for search (see 7.1)
  phone         TEXT,                    -- E.164 where possible
  phone_digits  TEXT,                    -- digits only, for partial match
  address       TEXT,
  note          TEXT,
  photo_path    TEXT,
  family_id     TEXT,                    -- groups related customers (C-5)
  slip_token    TEXT,                    -- walk-ins without phone
  created_at    INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL,
  deleted_at    INTEGER
);
CREATE INDEX idx_customer_phone ON customer(phone_digits);
CREATE INDEX idx_customer_name  ON customer(name_norm);

-- Garment types and measurement field templates (editable, M-1/M-4)
CREATE TABLE garment_type (
  id          TEXT PRIMARY KEY,
  key         TEXT NOT NULL UNIQUE,      -- 'panjabi','shirt',... or custom
  label_en    TEXT NOT NULL,
  label_bn    TEXT NOT NULL,
  is_builtin  INTEGER NOT NULL DEFAULT 0,
  sort_order  INTEGER NOT NULL DEFAULT 0,
  archived    INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE measurement_field (          -- template fields per garment
  id             TEXT PRIMARY KEY,
  garment_type_id TEXT NOT NULL REFERENCES garment_type(id),
  key            TEXT NOT NULL,          -- stable key, e.g. 'chest'
  label_en       TEXT NOT NULL,
  label_bn       TEXT NOT NULL,
  kind           TEXT NOT NULL,          -- 'length' | 'text' | 'choice'
  min_mm10       INTEGER,                -- soft range (4.4)
  max_mm10       INTEGER,
  sort_order     INTEGER NOT NULL,
  archived       INTEGER NOT NULL DEFAULT 0,
  UNIQUE (garment_type_id, key)
);

-- Measurements: APPEND-ONLY (H-1)
CREATE TABLE measurement_set (
  id              TEXT PRIMARY KEY,
  customer_id     TEXT NOT NULL REFERENCES customer(id),
  garment_type_id TEXT NOT NULL REFERENCES garment_type(id),
  version         INTEGER NOT NULL,      -- 1,2,3... per (customer, garment)
  taken_on        TEXT NOT NULL,         -- YYYY-MM-DD (backdate allowed, H-9)
  taken_by        TEXT,                  -- worker id or free text
  note            TEXT,
  display_unit    TEXT NOT NULL,         -- 'in' | 'cm' at time of entry
  fit_outcome     TEXT,                  -- NULL | 'confirmed' | 'altered' (H-6)
  status          TEXT NOT NULL DEFAULT 'active',  -- 'active' | 'error'
  supersedes_id   TEXT REFERENCES measurement_set(id),
  created_at      INTEGER NOT NULL,
  UNIQUE (customer_id, garment_type_id, version)
);
CREATE INDEX idx_mset_lookup
  ON measurement_set(customer_id, garment_type_id, taken_on DESC, version DESC);

CREATE TABLE measurement_value (
  set_id     TEXT NOT NULL REFERENCES measurement_set(id),
  field_key  TEXT NOT NULL,              -- copied key, NOT FK: survives template edits
  mm10       INTEGER,                    -- length values
  text_value TEXT,                       -- text/choice values
  PRIMARY KEY (set_id, field_key)
);

-- Orders
CREATE TABLE "order" (
  id            TEXT PRIMARY KEY,
  number        INTEGER NOT NULL,        -- human slip number, sequential per shop
  customer_id   TEXT NOT NULL REFERENCES customer(id),
  delivery_date TEXT NOT NULL,           -- YYYY-MM-DD
  trial_date    TEXT,
  discount      INTEGER NOT NULL DEFAULT 0,
  urgent        INTEGER NOT NULL DEFAULT 0,
  status        TEXT NOT NULL,           -- derived roll-up, kept for indexing
  note          TEXT,
  season_id     TEXT REFERENCES season(id),
  parent_order_id TEXT REFERENCES "order"(id),   -- alteration/remake (O-14)
  created_at    INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL,
  deleted_at    INTEGER,
  cancelled_at  INTEGER,
  cancel_reason TEXT,
  UNIQUE (number)
);
CREATE INDEX idx_order_delivery ON "order"(delivery_date) WHERE deleted_at IS NULL;
CREATE INDEX idx_order_customer ON "order"(customer_id);

CREATE TABLE order_item (
  id                 TEXT PRIMARY KEY,
  order_id           TEXT NOT NULL REFERENCES "order"(id),
  garment_type_id    TEXT NOT NULL REFERENCES garment_type(id),
  qty                INTEGER NOT NULL DEFAULT 1,
  price              INTEGER NOT NULL,   -- poisha, per line total
  measurement_set_id TEXT REFERENCES measurement_set(id),  -- the SNAPSHOT (H-8)
  fabric_source      TEXT,               -- 'shop' | 'customer'
  colour             TEXT,
  style_json         TEXT,               -- collar, pocket, cuff... (flexible)
  note               TEXT,
  status             TEXT NOT NULL,      -- received|cut|stitching|finishing|ready|delivered
  status_changed_at  INTEGER NOT NULL,
  worker_id          TEXT REFERENCES worker(id),
  work_units         INTEGER NOT NULL DEFAULT 100   -- capacity weight x100 (E-4/E-5)
);
CREATE INDEX idx_item_status ON order_item(status);

-- Payments: IMMUTABLE (corrections are new rows)
CREATE TABLE payment (
  id        TEXT PRIMARY KEY,
  order_id  TEXT NOT NULL REFERENCES "order"(id),
  amount    INTEGER NOT NULL,            -- poisha; negative for refunds
  kind      TEXT NOT NULL,               -- advance|payment|refund|adjustment
  method    TEXT NOT NULL,               -- cash|bkash|nagad|bank|other
  paid_on   TEXT NOT NULL,               -- YYYY-MM-DD
  note      TEXT,
  created_at INTEGER NOT NULL
);
CREATE INDEX idx_payment_order ON payment(order_id);

-- Attachments (photos)
CREATE TABLE attachment (
  id        TEXT PRIMARY KEY,
  owner_type TEXT NOT NULL,              -- 'order_item' | 'customer' | 'measurement_set'
  owner_id   TEXT NOT NULL,
  path       TEXT NOT NULL,              -- relative to app media dir
  thumb_path TEXT,
  created_at INTEGER NOT NULL
);

CREATE TABLE worker (
  id TEXT PRIMARY KEY, name TEXT NOT NULL, phone TEXT,
  specialty TEXT, active INTEGER NOT NULL DEFAULT 1, deleted_at INTEGER
);

CREATE TABLE season (
  id            TEXT PRIMARY KEY,
  name          TEXT NOT NULL,
  kind          TEXT NOT NULL,           -- eid_fitr|eid_adha|puja|wedding|custom
  target_date   TEXT NOT NULL,
  daily_capacity INTEGER NOT NULL,       -- work units / day (x100)
  working_days_mask INTEGER NOT NULL DEFAULT 127,   -- bit per weekday
  closed_dates_json TEXT,                -- holidays/closures
  active        INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE audit_log (                  -- B-7 (v1.1 UI, written from v1)
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  at INTEGER NOT NULL, entity TEXT NOT NULL, entity_id TEXT NOT NULL,
  action TEXT NOT NULL, diff_json TEXT
);

CREATE TABLE app_setting (key TEXT PRIMARY KEY, value TEXT NOT NULL);
```

### 4.3 Derived values, deliberately not stored
- **Order total** = Σ `order_item.price` − `discount`.
- **Paid** = Σ `payment.amount`. **Due** = total − paid. Computed in SQL views, so it cannot drift out of sync.
- **Customer due** = Σ due over that customer's non-cancelled, non-deleted orders.
- **Latest measurement** for (customer, garment) = highest `taken_on`, then `version`, where `status='active'`.

```sql
CREATE VIEW v_order_money AS
SELECT o.id AS order_id,
       COALESCE(SUM(i.price),0) - o.discount            AS total,
       COALESCE((SELECT SUM(amount) FROM payment p WHERE p.order_id=o.id),0) AS paid
FROM "order" o LEFT JOIN order_item i ON i.order_id = o.id
GROUP BY o.id;
```

`order.status` is the one denormalized roll-up (min status across items, `delivered` only when all are), maintained in the same transaction as any item status change, because the deliveries list filters on it.

## 5. Core Domain Logic

### 5.1 Measurement versioning (H-1, H-5, H-8)

**Save flow (single DB transaction):**
1. Read `max(version)` for (customer, garment); `version = max + 1`.
2. Insert `measurement_set` and its `measurement_value` rows.
3. Never `UPDATE`/`DELETE` existing set or value rows. Enforced by:
   - Repository exposes only `create()` and `markError()`; no update/delete methods exist.
   - DB triggers abort `UPDATE`/`DELETE` on `measurement_value`, and on `measurement_set` any update except `status` and `fit_outcome`.

```sql
CREATE TRIGGER trg_mvalue_no_update BEFORE UPDATE ON measurement_value
BEGIN SELECT RAISE(ABORT,'measurement_value is append-only'); END;
CREATE TRIGGER trg_mvalue_no_delete BEFORE DELETE ON measurement_value
BEGIN SELECT RAISE(ABORT,'measurement_value is append-only'); END;
```

**"Edit" in the UI** = prefill a new version from the latest one, user changes fields, save creates v(n+1) with `supersedes_id` set. If nothing changed, no new version is created ("No change" in Flow A just links the existing set to the order item).

**Snapshot (H-8):** `order_item.measurement_set_id` points at the exact immutable version used. Because versions never mutate, no copying is needed and old orders always show what was cut.

**Edge cases**
- *Backdated import (H-9):* `taken_on` may be earlier than existing versions. `version` stays creation-ordered; "latest" is by `taken_on` then `version`, so a backdated entry never hijacks "current".
- *Entered in error:* `status='error'` hides the set from latest/compare/trend; still visible in an "Include errors" toggle.
- *Template edits:* values key off `field_key` text, not field IDs, so renaming or archiving a template field never orphans history. Archived fields still render in old versions.

### 5.2 Diff engine (H-3)

Pure function in `domain/`:

```dart
List<FieldDelta> diff(MeasurementSet a, MeasurementSet b)
// FieldDelta { key, before: Length?, after: Length?, delta: Length?, kind: added|removed|changed|same }
```
Compares by `field_key`; works across garment types on shared keys. Warning rule (4.4): `|delta| > threshold(field)` triggers the "Confirm change?" prompt at save time. Default threshold 1.5 in (38 mm), configurable.

### 5.3 Length value object

```dart
class Length { final int mm10; ... }       // immutable
Length.fromInches(Fraction f)
String toInchFraction({int denominator = 8})  // "38½"
String toCm({int decimals = 1})
```
Display rounding never changes the stored value; only entry sets it. Fractions parsed from the custom keypad (½, ¼, ⅛, ¾...) into tenths-of-mm via `round(inches * 254)`.

### 5.4 Money

`Money(int poisha)` with `+`, `-`, comparison, `format(locale)` (Bangla digits and ৳ grouping `১,২৩,৪৫৬`, using the South Asian lakh/crore grouping). Arithmetic on ints only. Overpayment (paid > total) is allowed but shown as "credit".

### 5.5 Order lifecycle

```
Item: received → cut → stitching → finishing → ready → delivered
                 ↑ configurable; "simple mode" collapses to: received → in-progress → ready → delivered
Order: derived from items. cancelled is terminal.
```
- Transitions are free-forward and allow one-step-back (to fix mistakes). Each change writes `status_changed_at` and an `audit_log` row.
- **Deliver guard (P-4):** if `due > 0`, the UI offers *Collect & deliver* or *Deliver with due* (explicit confirm). The domain use case `DeliverOrder` enforces the confirm flag, so no other code path can skip it.
- **Cancel (O-12):** sets `cancelled_at`; use case requires a decision for any positive paid balance (create `refund` payment, or keep as forfeited via `adjustment` with reason).

### 5.6 Capacity engine for Eid-rush (E-3, E-4, E-5, E-6)

Pure, deterministic, unit-testable.

**Inputs:** season (`target_date`, `daily_capacity`, working-day mask, closed dates), the set of unfinished order items with their `delivery_date` and `work_units`, today's date.

**Work units:** a standard Panjabi = 100 (1.0). Per-garment weights editable (Sherwani 400, Blouse 60). Capacity and demand use the same unit, which is what makes the model honest for a mixed order book.

**Load per day**
```
committed(d) = Σ work_units of unfinished items with delivery_date = d
capacity(d)  = daily_capacity if d is a working day else 0
utilisation(d) = committed(d) / capacity(d)         (∞ if capacity 0 and committed > 0)
colour: <0.8 green · 0.8–1.0 amber · >1.0 red
```

**Earliest safe date for a new order (E-5):** work is done earliest-deadline-first, so a date `D` is safe for new work `w` iff for every day `t ≥ D` in the horizon, cumulative demand due on or before `t` (including `w`) ≤ cumulative capacity from today through `t`. Algorithm:

```
for D in today+minLeadDays .. target_date:
    if feasible(D, w): return D
return null   # nothing feasible before target → show "no safe date" + overbook warning
```
`feasible` walks a prefix-sum of capacity vs. demand, O(horizon) per candidate, so O(horizon²) worst case. With horizons ≤ 60 days this is trivial. Tailors can always override; an override on a red day requires a one-tap confirm and tags the order `overbooked`.

**Last date to accept orders (E-6):** largest `D` such that adding one standard unit is still feasible, shown as "Stop taking Eid orders after ...".

**At-risk (E-9):** for each unfinished item, remaining stage-work estimate vs. working days left. Stage weights (cut 20%, stitch 60%, finish 20%) are defaults. Flag if EDF simulation misses the item's date.

**v1.1:** per-worker capacity (assignment-aware) replaces the single `daily_capacity`; the engine takes `List<CapacityLane>` so v1 uses a single lane and v1.1 adds lanes without an interface change.

### 5.7 Reminders (D-2, D-4)

On any order create/edit/status change, a `ReminderScheduler` recomputes the set of scheduled notifications:
- Evening-before (default 7 pm) and morning-of (default 8 am) for each open delivery date, **grouped per date** ("5 deliveries tomorrow") to avoid notification spam.
- Daily 9 am overdue digest if any.
- Android caps and OEM battery killers drop alarms, so the schedule is *also* rebuilt at every app start and every boot (`RECEIVE_BOOT_COMPLETED`). Use inexact alarms with `SCHEDULE_EXACT_ALARM` requested only if granted; degrade silently. The dashboard's "Today" list is the source of truth either way; notifications are a convenience.
- Notification payload is a deep link `/orders/{id}` or `/deliveries/today`.

### 5.8 Outbound messages (D-3, M-10, P-6)

Template with placeholders (`{name}`, `{garment}`, `{due}`, `{shop}`) rendered in Dart, opened via `sms:` or `https://wa.me/<number>?text=...` URL launch. No API, no cost, user presses send themselves (also avoids any "sent on my behalf" surprises). Phone numbers normalized to E.164 using default country `BD` (+880) rules: strip leading `0`, handle `01XXXXXXXXX`.

## 6. Security and Privacy

| Concern | Design |
|---|---|
| Data at rest | SQLCipher AES-256. 32-byte random key generated at first run, stored in Keystore/Keychain via `flutter_secure_storage` |
| App lock | PIN (Argon2id/PBKDF2 hash in secure storage) and optional biometrics (`local_auth`); lock on background after configurable timeout. PIN gate is UI-level; DB key is not derived from PIN in v1 (avoids lockout = data loss) |
| Backups | File encrypted client-side (AES-256-GCM) with a key derived from a **user-chosen backup passphrase** (Argon2id). Uploaded to Drive `appDataFolder`. Passphrase is never stored; losing it means the backup is unreadable, so UI states this clearly and offers a printable recovery code |
| Photos | Stored in app-private directory (not the gallery), included in backups |
| Logging | No customer data in logs or crash reports. Crash reporting (if added) is scrubbed and opt-in |
| Permissions | Minimal: notifications, optional contacts, camera, and photos only when used. No location, no SMS read |
| Screenshots | `FLAG_SECURE` on measurement and payment screens is optional (setting) |

Threat model is a lost or shared shop phone and an accidental data wipe, not a nation-state. Backup passphrase design reflects that.

## 7. Search and Localization

### 7.1 Search (S-1, C-2)
- `name_norm`: lowercase, strip diacritics/zero-width joiners where safe, collapse whitespace; Bangla text is kept as-is but normalized (NFC, unify ড়/ড় and য়/য় composed vs. decomposed forms).
- **Bangla ↔ Latin matching:** optional transliteration key (`name_translit`) generated by a small phonetic map so "Rahim" finds "রহিম". Ship as P1; v1 uses prefix and substring match on both scripts.
- Phone: digits-only substring match on `phone_digits`.
- Implementation: SQLite **FTS5** virtual table over `name_norm` + `phone_digits` + order number, with a trigram or prefix index; fallback `LIKE` on small data. Target: <200 ms at 10k customers (well within SQLite's range with indexes).

### 7.2 Localization
- ARB files `app_en.arb`, `app_bn.arb`; `flutter_localizations` + `intl`.
- A single `DigitFormatter` converts to Bangla digits at the presentation boundary only; storage and parsing always use ASCII. The numeric keypad accepts both.
- Fonts: bundle **Noto Sans Bengali** subset (Regular/Bold) so rendering is consistent even on devices with poor Bangla system fonts. Budget ~400 KB.
- Date display: `dd MMM yyyy` with Bangla month names in `bn`. Week starts Saturday in `bn-BD` (configurable).

## 8. Backup and Restore (B-1…B-3, B-8)

**Backup artifact:** a single `.tkbackup` file (zip):
```
manifest.json     { schemaVersion, appVersion, createdAt, deviceId, counts, sha256s }
db.sqlite         (SQLCipher DB, exported via sqlcipher_export or VACUUM INTO)
media/            (photos + thumbs)
```
Whole zip encrypted as in section 6.

**Process:** `VACUUM INTO` a temp copy (consistent snapshot without stopping the app), zip with media, encrypt, upload. Incremental media upload keyed by sha256 to avoid re-sending photos (v1.1 optimization; v1 uploads full).

**Schedule:** WorkManager periodic job (daily, Wi-Fi + charging preferred) plus manual "Back up now". Failure surfaces as the red "Last backup" badge (>7 days).

**Restore:** download, decrypt with passphrase, verify checksums and `schemaVersion ≤ app's`, then replace the DB atomically (write to a temp file, fsync, swap, restart providers). If the backup is from an older schema, run forward migrations on the restored DB. Restore always keeps the previous DB as `pre_restore_<ts>.sqlite` for 7 days.

**Test requirement (CI):** restore round-trip test on every release build: seed DB → backup → wipe → restore → assert equal.

## 9. Migrations and Versioning

- Drift `MigrationStrategy` with explicit step-by-step migrations (`from1To2`, ...), each covered by a test that opens a fixture DB of the previous version, migrates, and checks invariants (row counts, view results, trigger presence).
- **Never destructive:** columns are added, not dropped, in v1.x; data transformations run inside a transaction with a pre-migration automatic local copy of the DB file.
- Backups carry `schemaVersion`; a newer-than-app backup is rejected with a clear "update the app" message.

## 10. Sync Design (v1.2, reserved now)

Not built in v1, but v1 choices keep it feasible:
- UUIDv7 IDs, `updated_at`/`rev`/`device_id` columns.
- Append-only measurement sets and immutable payments merge as **set unions** with no conflicts.
- Mutable entities (customer, order, order_item) use per-field last-writer-wins on `updated_at` with `device_id` tiebreak.
- Transport: operation log pushed to a small backend (e.g. Supabase/Firebase) or peer sync over local network for the shop-tablet case. Decision deferred until demand is validated.
- Order **numbers** conflict across devices; resolved by per-device prefix/range allocation (e.g. device A uses 1000–1999) or a `number` assigned on first sync with a local temporary label.

## 11. Performance Plan

| Area | Technique |
|---|---|
| Startup | Defer non-critical init (backup scheduler, notification rebuild) until after first frame; open DB on a background isolate (`drift` `NativeDatabase.createInBackground`) |
| Lists | `ListView.builder`, keyset pagination (`WHERE (delivery_date, id) > (?, ?)`), const widgets |
| Queries | Covering indexes for the hot paths (deliveries by date, dues by customer, latest measurement); `EXPLAIN QUERY PLAN` checked in tests for these |
| Images | Compress to ≤1280 px / ~300 KB on capture, 200 px thumbnails, decode with `cacheWidth` |
| Dashboard | One aggregated query per tile, streams debounced 100 ms |
| Memory | No full-table loads; measurement history paged per customer |
| Budget | Cold start < 2 s, frame time < 16 ms on a 2 GB reference device (e.g. Redmi 9A class); profiled in CI with a smoke benchmark |

Seed a 10k-customer / 50k-order synthetic DB for perf tests.

## 12. Testing Strategy

| Level | Coverage | Tools |
|---|---|---|
| Unit (domain) | `Length`, `Money`, diff engine, capacity engine (property tests: EDF feasibility never overbooks), state transitions, phone normalizer | `flutter_test`, `glados`/hand-rolled property tests |
| Data | Every DAO against in-memory Drift; trigger enforcement (append-only); migration tests; view correctness | Drift in-memory DB |
| Widget | Measurement keypad, compare view highlighting, order wizard validation, Bangla digit rendering (golden tests in `en` and `bn`) | `flutter_test`, `alchemist` goldens |
| Integration | Flow A (returning customer order < 60 s scripted), Flow C (compare), Flow D (deliver with due guard), backup/restore round-trip | `integration_test` on emulator |
| Manual | Real-tailor usability sessions on a cheap Android phone each milestone | — |

Quality gates in CI: `flutter analyze` with strict lints, coverage threshold on `domain/` (≥ 90%), no failing golden.

## 13. Delivery Plan

| Milestone | Contents | Exit criteria |
|---|---|---|
| **M0 — Foundations** (week 1–2) | Project skeleton, theme, l10n (en/bn), encrypted Drift DB, Money/Length types, CI | App boots, DB opens encrypted, tests green |
| **M1 — Customers + Measurements** (week 3–5) | Customer CRUD/search, measurement templates, fast keypad, versioning, history timeline, compare | Flow B and C work offline end-to-end |
| **M2 — Orders + Payments** (week 6–8) | Order wizard, items/status, snapshot linkage, advance/due, dues list, cutting slip PDF | Flow A under 60 s; due math verified |
| **M3 — Deliveries + Reminders** (week 9) | Today/week/overdue, local notifications, ready-message templates | Flow D works; reminders survive reboot |
| **M4 — Eid-rush** (week 10–11) | Season setup, capacity engine, load calendar, safe-date suggestion, rush list, batch lists | E-1…E-5, E-8, E-11 pass; engine property tests |
| **M5 — Backup + Hardening** (week 12) | Encrypted Drive backup/restore, app lock, perf pass, beta with 3–5 real shops | Restore round-trip in CI; startup/perf budgets met |

Timeline assumes one full-time developer; adjust accordingly.

## 14. Risks and Decisions Log

| # | Decision / Risk | Notes |
|---|---|---|
| D1 | Flutter + Drift + SQLCipher | Revisit only if a hard Flutter blocker appears on target devices |
| D2 | Lengths stored as integer 0.1 mm | Exact for inch fractions and cm; avoids float comparison bugs in diff |
| D3 | Measurement tables are append-only, DB-enforced | Core product promise; triggers are the safety net against future code mistakes |
| D4 | No backend in v1 | Zero running cost and full privacy; sync becomes a deliberate v1.2 project |
| D5 | Backup passphrase not recoverable | Trade-off: privacy vs. support burden; mitigated by recovery code print-out |
| R1 | OEM battery killers drop notifications on cheap Android | Dashboard is source of truth; rebuild alarms on start/boot; guide user to disable battery optimization |
| R2 | Drive `appDataFolder` requires Google sign-in | Offer local-file export (share to any storage) as fallback |
| R3 | Bangla search quality (spelling variants) | v1 substring, then transliteration key, then fuzzy; gather real queries |
| R4 | Capacity model oversimplifies reality | Single-lane v1 with overridable suggestions; real season data informs weights |
| R5 | Large photo libraries bloat backups | Compression at capture; optional "exclude photos from backup" |
| Q1 | Play Store only, or also direct APK for shops with limited Play access? | Affects update mechanism and signing |
| Q2 | Bluetooth thermal printer support priority | Would add platform channel work; PDF share is the baseline |
