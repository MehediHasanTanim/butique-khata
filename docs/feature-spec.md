# Tailor Khata — Feature Specification

> Order and measurement book for tailors and boutiques. Customer measurements (naap), order details, delivery dates, advance and due, and an Eid-rush view.

**Status:** Draft v0.1  **Platform:** Mobile (Android first, iOS later)  **Last updated:** 2026-10-22

---

## 1. Vision

Replace the paper khata (ledger notebook) that every tailor keeps. The notebook has three jobs: remember a customer's measurements, remember what was promised and by when, and remember who owes money. Paper fails at all three when the shop gets busy, especially before Eid.

**Core promise:** open the app, find any customer in seconds, see their last measurements and every past order, and know exactly what is due this week.

**The measurement history is the heart of the product.** Everything else (orders, payments, rush view) is table stakes. If a regular customer walks in and the tailor can pull up every measurement taken over the last five years, with the changes between them, the app has paid for itself.

## 2. Target Users

| Persona | Description | Needs |
|---|---|---|
| **Owner-tailor** (primary) | Runs a small tailoring shop, 1–5 workers, often not tech-savvy, may prefer Bangla | Fast entry, big buttons, works offline, no accounting jargon |
| **Boutique owner** | Takes orders, sends work to karigors (artisans/workers), handles female customers' dresses | Per-garment detail, design notes, reference photos, karigor assignment |
| **Karigor / cutting master** (secondary, v2) | Cuts and stitches | Sees only the work assigned to them, with measurements |

### Design constraints derived from the users
- One-hand, standing-at-the-counter use. Large touch targets, minimal typing.
- Must work with **no internet** (spotty connectivity, shops in markets/basements).
- Bangla and English UI, with Bangla digits optional.
- Low-end Android devices (2–3 GB RAM) must feel fast.
- Entering a new order must take under 60 seconds for a returning customer.

## 3. Goals and Non-Goals

### Goals (v1)
1. Digitize customers, measurements, orders, delivery dates, and payments.
2. Make measurement history searchable, comparable, and never lost.
3. Provide an Eid-rush view that shows capacity vs. promised deliveries.
4. Work fully offline with safe backup.

### Non-Goals (v1)
- Full accounting, GST/VAT invoicing, payroll, or inventory/fabric stock management.
- Online storefront or customer-facing app.
- Multi-branch management.
- Payment gateway integration (bKash/Nagad are recorded as a payment *method*, not processed).

## 4. Core Concepts (Domain Model)

```
Customer 1───* MeasurementSet (versioned, per garment type)
Customer 1───* Order 1───* OrderItem (one garment each)
OrderItem *───1 MeasurementSet (snapshot used for that item)
Order 1───* Payment
Order *───0..1 Worker (karigor)
```

- **Customer** — a person (or family; see Family Profiles).
- **MeasurementSet** — a dated set of measurements for a garment type (e.g. Panjabi, Shirt, Pant, Blouse, Salwar Kameez). Immutable once saved; changes create a new version.
- **Order** — one visit/transaction: one or more garments, a delivery date, pricing, payments.
- **OrderItem** — a single garment with its own style details, fabric, price, and status.
- **Payment** — advance or later installment against an order.

## 5. Feature Specification

Priority legend: **P0** = must ship in v1, **P1** = v1 if time allows, **P2** = later.

### 5.1 Customer Book

| ID | Feature | Priority |
|---|---|---|
| C-1 | Create customer with name, phone, optional photo, address, notes | P0 |
| C-2 | Search by name or phone (partial match, Bangla and English, fuzzy) | P0 |
| C-3 | Customer profile screen: measurements, order history, total due, last visit | P0 |
| C-4 | Quick-add from phone contacts | P1 |
| C-5 | **Family profiles**: link customers (e.g. father and sons, mother and daughters) so the tailor can switch between them fast | P1 |
| C-6 | Tags (VIP, wedding party, difficult fit, bulk buyer) | P1 |
| C-7 | Birthday/anniversary reminders | P2 |
| C-8 | Duplicate detection on phone number | P0 |

**Notes:** Phone number is not required (walk-in customers) but strongly encouraged. Allow a customer with only a name and a "token/slip number".

### 5.2 Measurements (Naap) — the flagship feature

#### 5.2.1 Capture

| ID | Feature | Priority |
|---|---|---|
| M-1 | Measurement templates per garment type with the correct fields in the correct order (see 5.2.5) | P0 |
| M-2 | Numeric entry optimized for speed: custom keypad with fractions (½, ¼, ⅛ and decimals), auto-advance to next field | P0 |
| M-3 | Unit support: inch (default), cm; per-field toggle and global setting. Store canonical value, display in preference. | P0 |
| M-4 | Custom fields: owner can add/remove/reorder fields in a template (e.g. "collar style", "cuff width") | P0 |
| M-5 | Free-text note per measurement set ("left shoulder lower", "wants loose fit") | P0 |
| M-6 | Optional photo of customer or posture note | P1 |
| M-7 | Voice input for measurements, dictated in Bangla/English while the tailor's hands are busy with the tape | P2 |
| M-8 | Body-profile reuse: one body measurement set that feeds multiple garments (chest, waist, hip shared) | P1 |

#### 5.2.2 History (the core value)

| ID | Feature | Priority |
|---|---|---|
| H-1 | **Every save creates a new dated version. Nothing is ever overwritten or deleted by an edit.** | P0 |
| H-2 | Timeline view per customer per garment type: date, who measured, linked order | P0 |
| H-3 | **Side-by-side compare** of any two versions with changed values highlighted and the delta shown (e.g. chest 38 → 40, +2) | P0 |
| H-4 | **Trend view**: line chart of a single field over time (waist over 3 years) | P1 |
| H-5 | "Use last measurements" when creating a new order, with a one-tap prompt "Has anything changed?" | P0 |
| H-6 | Mark a version as "fit confirmed" after delivery (the garment fitted well) vs. "needed alteration". Over time the app shows the **best-fit measurement** for that customer. | P1 |
| H-7 | Alteration log: after-delivery adjustments (sleeve shortened 0.5") optionally written back into a new version | P1 |
| H-8 | Each OrderItem stores a **snapshot** of the measurements used, so old orders always show what was actually cut, even if the customer's current numbers change | P0 |
| H-9 | Import old paper-book measurements with a backdated date ("recorded earlier") | P0 |
| H-10 | Export a customer's full measurement history as PDF/image to share or print | P1 |

**Rules**
- Versions are append-only. A mistaken entry can be flagged "entered in error" (hidden from compare/trend, still in audit trail), not deleted.
- Compare view works across garment types only for shared fields (chest, waist, etc.).
- The "latest" measurement for a customer and garment is the most recent non-error version.

#### 5.2.3 Sharing and print
| ID | Feature | Priority |
|---|---|---|
| M-9 | Printable/shareable **cutting slip** (garment, measurements, style notes, delivery date, order no.) for the karigor | P0 |
| M-10 | Share measurement card to the customer via WhatsApp/SMS (image or text) | P1 |

#### 5.2.4 Validation
- Soft range checks per field (e.g. shirt chest 20–60 in). Warn on out-of-range, never block.
- Warn if a value differs from the previous version by more than a configurable threshold ("Chest changed by 6 inches. Confirm?").

#### 5.2.5 Default garment templates (editable)

| Garment | Default fields |
|---|---|
| **Panjabi / Kurta** | Length, Chest, Waist, Hip, Shoulder, Sleeve, Cuff/Mori, Collar, Neck, Bottom |
| **Shirt** | Length, Chest, Waist, Hip, Shoulder, Sleeve, Cuff, Collar |
| **Pant / Trouser** | Length, Waist, Hip, Thigh, Knee, Bottom/Mohri, Rise, Fly |
| **Pajama / Payjama** | Length, Waist, Hip, Thigh, Bottom |
| **Blazer / Coat** | Length, Chest, Waist, Shoulder, Sleeve, Back |
| **Salwar Kameez** | Kameez length, Chest/Bust, Waist, Hip, Shoulder, Sleeve, Armhole, Neck front, Neck back; Salwar length, Waist, Hip, Bottom |
| **Blouse** | Length, Bust, Waist, Shoulder, Sleeve, Armhole, Neck front, Neck back, Dart point |
| **Custom** | Owner-defined |

Bangla field labels shipped by default (e.g. লম্বা, বুক, কোমর, কাঁধ, হাতা, গলা). Labels are editable per shop.

### 5.3 Orders

| ID | Feature | Priority |
|---|---|---|
| O-1 | Create order for a customer with one or more items | P0 |
| O-2 | Per item: garment type, quantity, fabric (own fabric / shop fabric), colour, style options (collar type, pocket, cuff, buttons, lining, embroidery), free-text note | P0 |
| O-3 | Attach reference photos (design picture, fabric swatch, customer-provided sample) | P0 |
| O-4 | Per-item price; order total with optional discount | P0 |
| O-5 | **Delivery date** (required) with optional "trial date" for fitting | P0 |
| O-6 | Auto-generated order number / slip number (shop-prefix, sequential, shown in large print for the slip) | P0 |
| O-7 | Order status pipeline per item: **Received → Cut → Stitching → Finishing → Ready → Delivered** (customisable; simple 3-step mode available) | P0 |
| O-8 | Bulk status update (mark 10 items Ready in one go) | P0 |
| O-9 | Assign to worker/karigor | P1 |
| O-10 | Urgent flag (rush charge optional) | P1 |
| O-11 | Edit order after creation with change log | P0 |
| O-12 | Cancel order with reason; advance handling prompt (refund or keep) | P0 |
| O-13 | Duplicate a previous order ("same as last Eid") | P0 |
| O-14 | Alteration / remake order linked to the original | P1 |
| O-15 | Customer-owned fabric tracking: record length received and leftover returned | P2 |

### 5.4 Payments: Advance and Due

| ID | Feature | Priority |
|---|---|---|
| P-1 | Record advance at order time (amount, method: cash / bKash / Nagad / bank / other, date) | P0 |
| P-2 | Record additional payments any time against an order | P0 |
| P-3 | Auto-computed **Due = Total − Σ payments**, shown on every order card in a clear colour (red due, green paid) | P0 |
| P-4 | Block or warn on "mark Delivered" when due > 0, with a one-tap "collect now" | P0 |
| P-5 | **Customer-level due**: sum of dues across all orders; "Who owes me money" list sorted by amount and age | P0 |
| P-6 | Payment receipt (shareable image/PDF/SMS text) | P1 |
| P-7 | Refunds and adjustments, recorded as negative payments with a reason | P1 |
| P-8 | Daily cash summary: collected today by method | P1 |
| P-9 | Write-off of small dues with reason | P2 |

Currency: BDT (৳) by default, configurable. Amounts stored as integers in the smallest sensible unit (paisa) to avoid float errors.

### 5.5 Delivery and Reminders

| ID | Feature | Priority |
|---|---|---|
| D-1 | **Today / Tomorrow / This Week / Overdue** list of deliveries | P0 |
| D-2 | Local push notification the evening before and the morning of deliveries | P0 |
| D-3 | "Ready" → one-tap message to the customer ("Your Panjabi is ready, due ৳1,200") via SMS or WhatsApp link with a prefilled template | P0 |
| D-4 | Overdue alerts when a promised date is past and status is not Ready/Delivered | P0 |
| D-5 | Reschedule delivery with reason and optional notification to customer | P1 |
| D-6 | Uncollected garments list (Ready but not picked up for N days) | P1 |
| D-7 | Delivery mark with optional signature/photo | P2 |

### 5.6 Eid-Rush View

The seasonal killer feature. Before Eid, orders pile up and tailors over-promise. This view shows **capacity vs. commitments** so the tailor stops accepting orders that cannot be finished.

| ID | Feature | Priority |
|---|---|---|
| E-1 | **Rush mode**: season toggle (Eid-ul-Fitr, Eid-ul-Adha, Puja, Pohela Boishakh, wedding season, custom) with a target date | P0 |
| E-2 | **Countdown board**: days left, orders remaining by status, count of garments not yet cut | P0 |
| E-3 | **Day-by-day load calendar**: for each date, garments due vs. daily capacity, colour-coded (green under, amber near, red over) | P0 |
| E-4 | Set daily capacity (garments per day, optionally per garment type or per worker) | P0 |
| E-5 | **Smart delivery date suggestion** when creating an order during rush: "Earliest safe date: 14 Mar" based on remaining capacity | P0 |
| E-6 | "Last date to accept new orders" indicator, computed from capacity and backlog | P1 |
| E-7 | **Production board** (kanban): cards by status for rapid drag/swipe updates, filter by karigor | P1 |
| E-8 | Group by garment type: "37 Panjabi, 12 Pant, 8 Blouse to cut" for batch cutting | P0 |
| E-9 | At-risk list: orders where remaining work vs. remaining days looks impossible | P1 |
| E-10 | Rush-day cash summary: total due vs. collected | P1 |
| E-11 | Compact **rush list** mode: one line per order, large text, sort by delivery date; designed for a glance during chaos | P0 |
| E-12 | Season report afterwards (orders, revenue, on-time %, busiest day) | P2 |
| E-13 | Auto-suggest rush charge for orders under N days | P2 |

**Capacity model (v1, simple):** `daily_capacity` (garments/day) × working days between today and target date, minus garments already committed. Per-worker and per-garment weights (a Sherwani counts as 4 Panjabis) are P1.

### 5.7 Search, Filters, Dashboard

| ID | Feature | Priority |
|---|---|---|
| S-1 | Global search: customer name, phone, order no. | P0 |
| S-2 | Filters: status, delivery date range, due > 0, garment type, worker | P0 |
| S-3 | **Home dashboard**: today's deliveries, overdue count, total due outstanding, orders received today, quick actions (New order, New customer) | P0 |
| S-4 | Simple reports: sales by day/month, outstanding dues, popular garments | P1 |

### 5.8 Workers (karigors) — P1

- Add workers with name, phone, specialty.
- Assign items; each worker's load visible in the rush view.
- Optional piece-rate tracking (pay per garment) with a monthly tally. (P2)

### 5.9 Settings and Shop Profile

- Shop name, logo, address, phone (printed on slips and receipts).
- Language: Bangla / English. Digits: Bangla / Latin.
- Default unit, currency, order-number prefix.
- Garment templates and status pipeline customisation.
- Message templates (ready, reminder, due).
- Notification times.
- App lock (PIN / biometric), because the data is the shop's livelihood and customers' private information.

### 5.10 Data, Backup, and Sync

| ID | Feature | Priority |
|---|---|---|
| B-1 | **Offline-first**: all features work with no connection; local database is the source of truth | P0 |
| B-2 | Manual and scheduled **backup** to Google Drive (Android) / iCloud (iOS), encrypted | P0 |
| B-3 | One-tap **restore** on a new phone | P0 |
| B-4 | Export to Excel/CSV: customers, orders, payments, measurements | P1 |
| B-5 | Cloud sync across two devices (owner phone and shop tablet) with conflict handling (last-write-wins per field, append-only measurement versions never conflict) | P1 |
| B-6 | Import from CSV/Excel to migrate from other tools | P2 |
| B-7 | Audit trail of edits and deletions (who, when, what changed) | P1 |
| B-8 | Soft delete with 30-day recovery for customers and orders | P0 |

Losing a tailor's measurement history is the worst failure this product can have, so backup prompts are persistent and visible (a "last backed up" badge on the home screen, warning after 7 days).

## 6. Key User Flows

### Flow A: Returning customer, new order (target < 60 s)
1. Home → Search "Rahim" → select customer.
2. Tap **New Order** → choose garment (Panjabi).
3. App shows last Panjabi measurements with date ("Taken 14 Mar 2025") → tap **No change** (or **Edit**, which opens a new version prefilled).
4. Pick style options (defaults from last order), enter price, set delivery date (Eid-rush suggests a date).
5. Enter advance → Save → print/share slip.

### Flow B: New customer, first measurements
Home → New customer (name, phone) → New Order → blank template → enter measurements with the fast keypad → continue as above.

### Flow C: Customer returns months later, fit has changed
Customer profile → Measurements → select Panjabi → **Compare** latest vs. two years ago → see chest +3", waist +4" → take new measurements → saved as a new version, history intact.

### Flow D: Delivery day
Home shows Today's deliveries → tap order → **Mark Ready** → "Send message to customer" → on pickup tap **Collect due** → **Delivered**.

### Flow E: Eid rush
Enable Rush mode (Eid, target date) → set capacity → every new order shows the earliest safe date and the load calendar turns red on overbooked days → daily check of the production board and rush list.

## 7. Screens (v1 inventory)

1. Home / Dashboard
2. Customer list + search
3. Customer profile (tabs: Overview, Measurements, Orders, Payments)
4. Measurement entry
5. Measurement history timeline + Compare + Trend
6. New order wizard (garment → measurements → details → price & advance → delivery)
7. Order detail (items, status, payments, change log)
8. Deliveries (Today / Week / Overdue)
9. Dues list
10. Eid-rush: countdown, load calendar, production board, rush list
11. Workers
12. Reports
13. Settings, templates, backup/restore

## 8. Non-Functional Requirements

| Area | Requirement |
|---|---|
| **Offline** | 100% of core flows functional without network |
| **Performance** | Cold start < 2 s on a 2 GB RAM Android device; search results < 200 ms with 10,000 customers |
| **Reliability** | No data loss on crash or kill mid-entry; autosave drafts of orders and measurements |
| **Storage** | Photos compressed (max ~300 KB each), thumbnails cached |
| **Localization** | Full Bangla and English strings, Bangla numerals, locale date formats, Bangla search |
| **Accessibility** | Min 48dp targets, high-contrast mode, scalable text (older users) |
| **Privacy** | Data stays on-device by default; backups encrypted; no analytics on customer data; app lock |
| **Security** | Local DB encryption at rest; secure backup key handling |
| **Compatibility** | Android 8+ first; iOS 15+ later |

## 9. Suggested Technical Direction (non-binding)

- **Framework:** Flutter (single codebase, good low-end Android performance, strong Bangla text support) or React Native.
- **Local DB:** SQLite (via Drift/Room) with an append-only `measurement_version` table; SQLCipher for encryption.
- **Sync (P1):** per-record version vectors or an operation log; measurement versions are insert-only so they merge trivially.
- **Backup:** serialize DB to an encrypted file, upload to the user's own Drive/iCloud.
- **Notifications:** local scheduled notifications (no server needed for v1).
- **Messaging:** deep links (`sms:`, `https://wa.me/`) with prefilled text; no API cost.

### Data sketch

```
customer(id, name, phone, photo, address, notes, family_id, created_at, deleted_at)
measurement_set(id, customer_id, garment_type, version, taken_on, taken_by,
                unit, note, status[active|error], created_at)
measurement_value(set_id, field_key, value_numeric)
order(id, number, customer_id, created_at, delivery_date, trial_date,
      total, discount, status, urgent, note, deleted_at)
order_item(id, order_id, garment_type, qty, price, measurement_set_id,
           style_json, fabric, status, worker_id)
payment(id, order_id, amount, method, paid_on, kind[advance|payment|refund], note)
worker(id, name, phone)
season(id, name, target_date, daily_capacity)
```

## 10. Release Plan

### MVP (v1.0) — "Replace the notebook"
Customer book, full measurement capture **with history and compare**, orders with delivery date, advance/due, deliveries list with reminders, basic **Eid-rush view** (countdown, load calendar, rush list, date suggestion), search, backup/restore, Bangla + English.

### v1.1 — "Run the rush"
Workers and assignment, production board, family profiles, trend charts, fit-confirmed/alteration tracking, receipts, WhatsApp/SMS templates, Excel export.

### v1.2 — "Run the shop"
Multi-device sync, reports, audit trail, voice measurement input, customer-fabric tracking, iOS release.

## 11. Success Metrics

- **Activation:** a new user enters a customer + measurement + order within 10 minutes of install.
- **Core value:** ≥ 60% of returning-customer orders start from a prior measurement set (shows history is used).
- **Retention:** weekly active use through a full season; shops still logging orders 4 weeks after install.
- **Rush:** % of rush-season orders delivered on or before the promised date.
- **Safety:** backup completed in the last 7 days for ≥ 80% of active shops.

## 12. Risks and Open Questions

| Risk / Question | Mitigation / Next step |
|---|---|
| Tailors may resist typing vs. paper | Ultra-fast entry, large keypad, show a clear payoff (history, dues); on-site usability tests with real tailors |
| Measurement fields differ across shops and regions | Fully editable templates; ship sensible defaults; collect feedback |
| Data loss = trust loss | Persistent backup nudges, restore tested on every release |
| Female customers' privacy (photos, body measurements) | No photo requirement; app lock; clear privacy defaults |
| Monetisation | Undecided: free core + paid Rush/Sync/Workers tier, or one-time unlock. Decide before v1.1 |
| Do shops need printed slips (Bluetooth thermal printer)? | Validate in interviews; PDF/image share is the v1 fallback |
| Capacity model accuracy | Start simple (garments/day); refine with real rush data |
| Bangla voice recognition quality | Keep P2; evaluate on-device models later |

**Open questions for the product owner**
1. Android only for v1, or both platforms?
2. Boutique-style garments (heavy embroidery, multi-stage work) or simple men's tailoring first?
3. Is the first user the owner alone, or do workers log in too?
4. Is a printed slip required at launch?
5. Free, ad-free, subscription, or one-time purchase?
