# Tailor Khata

Order and measurement book for tailors and boutiques: customer measurements (naap) with full history, orders, delivery dates, advance/due and an Eid-rush view. Offline-first, Bangla and English.

Docs: [feature spec](docs/feature-spec.md) · [technical design](docs/technical-design.md) · [implementation plan](docs/implementation-plan.md)

## Status

| Sprint | State |
|---|---|
| S0 Foundations | Done (S0-12 cold-start baseline on a real phone still to do) |
| S1 Customers + measurement capture | Done: customer book with FTS search, templates for 7 garments, fast keypad, append-only versioned measurements |
| S3 Orders + payments | Done, including photo attachments and the cutting slip (shared as a picture, not a PDF): order wizard, status pipeline, advance/due, payments, cancel, duplicate, dues list |
| S4 Deliveries, reminders, dashboard | Done: dashboard, delivery tabs, guarded delivery, customer messages (SMS/WhatsApp), local reminders, filters and search |
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

## Debug tools

In debug builds, **More → Developer tools** generates synthetic Bangla/English customers (100 / 1,000 / 10,000), saves them to the database and can remove them again.
