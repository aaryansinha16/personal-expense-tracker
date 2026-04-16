# Personal Expense Tracker

A local-first Android expense tracker built with Flutter. Tracks income and expenses, auto-detects transactions from bank/UPI SMS, and gives you monthly analytics — all stored locally on your device.

> **Status:** under active development. Being built PR-by-PR from the issues list.

## Goals
- Auto-detect transactions from UPI + bank + credit-card SMS (HDFC, SBI, ICICI, Axis, Kotak, PhonePe, GPay, Paytm, CRED, etc.)
- Manual entry for cash / corrections / income
- Monthly / weekly / yearly analytics with charts
- Per-category budgets with over-budget warnings
- No cloud, no accounts — everything stays on the device

## Stack
- Flutter 3.29+ (Android only — iOS can't read SMS)
- SQLite (`sqflite`) for local storage
- `another_telephony` for SMS inbox read + live listener
- `fl_chart` for charts
- `provider` for state

## Dev
```sh
flutter pub get
flutter test
flutter build apk --release
```
