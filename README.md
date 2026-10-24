# Tailor Khata

Order and measurement book for tailors and boutiques: customer measurements (naap) with full history, orders, delivery dates, advance/due and an Eid-rush view. Offline-first, Bangla and English.

Docs: [feature spec](docs/feature-spec.md) · [technical design](docs/technical-design.md) · [implementation plan](docs/implementation-plan.md)

## Status

| Sprint | State |
|---|---|
| S0 Foundations | Done (S0-12 cold-start baseline on a real phone still to do) |
| S1 Customers + measurement capture | Done: customer book with FTS search, templates for 7 garments, fast keypad, append-only versioned measurements |
| S3 Orders + payments | Done, including photo attachments and the cutting slip (shared as a picture, not a PDF): order wizard, status pipeline, advance/due, payments, cancel, duplicate, dues list |
| S5 Eid-rush | Done (P0): season setup, capacity engine, countdown board, load calendar, safe-date suggestion in the order wizard, batch lists, rush list. P1 items (production board, at-risk list, rush-day cash summary) and the tailor usability session are left for v1.1 |
| S4 Deliveries, reminders, dashboard | Done: dashboard, delivery tabs, guarded delivery, customer messages (SMS/WhatsApp), local reminders, filters and search |
| S6 Backup, security, hardening | Done except Google Drive upload (S6-02), scheduled background backup (S6-03) and beta distribution (S6-11); see notes below. Encrypted backup and restore, app lock, recently-deleted recovery, CSV export, query-plan and performance checks, accessibility and translation audit |
| S2 Measurement history | Done except S2-10 (PDF/image export) and S2-12 (tailor usability session): timeline, compare, trend, error flag, fit result, change prompts |

## Setup

Requirements: Flutter (stable, Dart 3.13+), Android SDK for device builds.

```bash
./scripts/codegen.sh        # pub get + build_runner + gen-l10n (generated files are not committed)
flutter run --flavor dev -t lib/main_dev.dart
```

| Flavor | Entry point | Application id |
|---|---|---|
| `dev` | `lib/main_dev.dart` | `com.tailorkhata.app.dev` |
| `prod` | `lib/main.dart` | `com.tailorkhata.app` |

Flavors are configured for Android. iOS flavors are deferred (Android first).

## Everyday commands

```bash
flutter analyze --fatal-infos     # strict lints, must be clean
flutter test                      # unit + widget + encrypted-DB tests
flutter test --coverage
dart run build_runner watch       # regenerate Drift/freezed code while editing
flutter gen-l10n                  # after editing lib/l10n/*.arb
```

## Project layout

```
lib/
  app/        bootstrap, app widget, router, shell, global providers, error boundary
  core/       db (encrypted Drift), money, units (Length/Fraction), time, l10n, logging, errors, ui
  features/   customers, measurements, orders, payments, deliveries, rush, settings, backup
              each with data/ domain/ presentation/
  l10n/       app_en.arb, app_bn.arb (generated code lands in lib/l10n/gen, not committed)
test/
```

`domain/` code must not import Flutter or Drift.

## Key decisions

- **Encryption:** the database uses SQLCipher through `package:sqlite3`'s hook (`hooks.user_defines.sqlite3.source: sqlcipher` in `pubspec.yaml`). The 256-bit key is generated on first run and kept in the Android Keystore / iOS Keychain. The app refuses to open if SQLCipher is not linked, so data can never be silently stored unencrypted.
- **Lengths** are integers in 0.1 mm units (1 inch = 254), **money** is integer poisha. No floats for stored values.
- **Bangla digits** are applied only at display time; storage and parsing use ASCII.
- **Backups** are one `.tkbackup` file: a small custom bundle (manifest, database snapshot, photos) encrypted in 1 MiB chunks with AES-256-GCM under a key from the backup passphrase (Argon2id). The database snapshot is exported already encrypted with that key (SQLCipher `sqlcipher_export`), so no readable copy of the data is ever written to disk. Only the derived key is kept on the phone (in the Keystore/Keychain), never the passphrase; restoring on another phone needs the passphrase typed in. A restore decrypts, checks every checksum and the schema version, opens the result with the current migrations and compares row counts, and only then swaps it in (the old database is kept for 7 days as `pre_restore_*.db`). A wrong passphrase or a damaged file changes nothing.
- **App lock:** the PIN is stored as a salted PBKDF2-HMAC-SHA256 hash in the Keystore/Keychain (not in the database it protects). Five wrong PINs start a lockout (30 s, doubling to 15 min) that survives closing the app. Forgot the PIN: the phone's own screen lock confirms ownership and removes the lock; the data is never touched.
- A startup failure (e.g. wrong key) shows an error screen and never deletes data.

## What works today

- Customers: add/edit, duplicate-phone warning, swipe to delete with undo (soft delete), search by name (English or Bangla prefix) or phone digits.
- Measurements: pick a garment, type with the custom keypad (digits, ⅛ ¼ ⅜ ½ ⅝ ¾ ⅞, decimals, inch/cm), soft range warnings, date and note, save a new version. Starts from the latest version.
- History: every version per garment on a timeline with what changed, side-by-side compare of any two versions, a trend chart per field, "entered in error" (hidden, reversible, audit-logged) and a fit result (confirmed / needed alteration). Saving unchanged values creates no new version, and a field that moved more than 1.5 in asks for confirmation.
- Everything works offline and in English and Bangla.

- Orders: a four-step wizard (garments → measurements, "no change" or edit → style, fabric, colour and price → delivery date, advance and payment). Each garment is cut from an exact, immutable measurement version. Order screen with per-garment progress (received → delivered, one step back allowed), payments and refunds, cancel with refund-or-keep, change-delivery with a change log, duplicate order. Orders tab lists open orders by delivery date; the Dues tab shows who owes what.

- Deliveries: the Home screen shows what is due today, overdue, owed and received today. Deliveries has Today / Tomorrow / This week / Overdue / Uncollected tabs. "Mark ready" offers a prefilled SMS or WhatsApp message (wording editable in More → Messages & shop); "Deliver" refuses to hand over unpaid work without an explicit choice (collect and deliver, or deliver with the balance still owing). Moving a delivery date can notify the customer and records the reason.
- Reminders: local notifications the evening before and the morning of delivery days (grouped per day) plus a daily overdue nudge. Times are set in More → Reminders; the schedule is rebuilt at app start and whenever orders change. The Home screen is the source of truth if the phone suppresses notifications.
- Photos and slips: attach design photos to each garment (camera or gallery; stored compressed in the app's private folder). The cutting slip combines order, style, exact measurements and photos on one page and is shared as a picture.
- Search: Home search finds customers and orders; the Orders tab filters by status, balance, garment and delivery dates.

- Eid-rush: set up a season (kind, deadline, garments per day, days off and closed dates, and how much work each garment is: a blazer 2.5, a blouse 0.6). The Rush tab shows days left, how many more garments fit, and garments by stage. The load calendar colours each day by how full the plan is (judged cumulatively, because garments are made before their due day). New orders get the earliest safe delivery date pre-filled; taking an order for a full date needs one confirmation and tags it "Over capacity". Batch lists group garments by stage and type ("37 Panjabi to cut") with one-tap moves; the rush list is one big line per order and swiping right moves it along.

## Debug tools

In debug builds, **More → Developer tools** generates synthetic Bangla/English customers (100 / 1,000 / 10,000), saves them to the database and can remove them again.

- Backup and restore (More → Backup & restore): set a passphrase once (or let the app make one), then "Back up now" or leave automatic backup on (once a day, when the app opens or returns to the foreground; the newest five automatic files are kept). Each file can be shared to WhatsApp, Drive or a computer. Home warns when there has been no backup for a week. Restore picks a `.tkbackup` file from anywhere, asks for the passphrase and a final confirmation, and restarts the app on the restored data.
- App lock (More → App lock): PIN, optional fingerprint/face, lock after leaving the app immediately or after 1, 5 or 15 minutes.
- Recently deleted (More): deleted customers can be brought back. A customer with no measurements, orders or photos is removed for good after 30 days; one with any history is kept until restored.
- Export (More → Export to spreadsheet): a zip of `customers.csv`, `orders.csv`, `payments.csv` and `measurements.csv` (UTF-8 with a byte-order mark so Excel shows Bangla; cells that could run as spreadsheet formulas are defused), shared through the system share sheet.

### Sprint 6 notes

- **Google Drive (S6-02) is not built.** It needs a Google Cloud project, OAuth consent and the app's signing certificate, which cannot be set up from the repository. The backup file can be shared to Drive (or anywhere) from the share sheet and restored from any file picker, which covers the "local-file fallback" the plan allows.
- **Scheduled backup (S6-03) is opportunistic**, not WorkManager: it runs when the app opens or returns to the foreground and the last backup is over a day old. A phone that is never opened is not backed up, which the Home warning makes visible.
- **S6-11 (beta distribution, crash reporting, feedback form)** is not done; it needs a Play Console track and a reporting backend.
- Performance and query-plan checks run on a desktop SQLite with 10,000 customers and 50,000 orders (`test/core/query_plan_test.dart`). The reference-device cold-start and frame-time measurements still need a real phone, as does the backup, wipe, restore round trip on hardware.
