# Tailor Khata

Order and measurement book for tailors and boutiques: customer measurements (naap) with full history, orders, delivery dates, advance/due and an Eid-rush view. Offline-first, Bangla and English.

Docs: [feature spec](docs/feature-spec.md) · [technical design](docs/technical-design.md) · [implementation plan](docs/implementation-plan.md)

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

## Debug tools

In debug builds, **More → Developer tools** generates synthetic Bangla/English customers and times it (the perf-harness stub; persistence arrives with the customer table in Sprint 1).
