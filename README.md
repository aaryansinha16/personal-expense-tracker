# Personal Expense Tracker

A local-first Android expense tracker built with Flutter. Tracks income and expenses, auto-detects transactions from bank/UPI SMS, and gives you monthly analytics — all stored locally on your device.

![Build APK](https://github.com/aaryansinha16/personal-expense-tracker/actions/workflows/build-apk.yml/badge.svg)

## Features
- Auto-imports transactions from UPI + bank + credit-card SMS (HDFC, SBI, ICICI, Axis, Kotak, PhonePe, GPay, Paytm, CRED, etc.)
- Manual entry for cash / corrections / income
- Week / month / year analytics: pie by category, daily-spend line chart, per-category progress bars
- Per-category monthly budgets with over-budget warnings
- SMS review queue teaches the app — categorizing once auto-categorizes future SMS from the same merchant
- Credit-card bill-statement SMS detected separately from regular spend
- Everything is local. No cloud, no accounts, no internet needed.

## Install on your phone (no USB needed)
1. Go to the **[Actions tab](https://github.com/aaryansinha16/personal-expense-tracker/actions)** of this repo on your phone.
2. Open the latest successful **Build APK** run.
3. Under **Artifacts**, download `expense-tracker-apk.zip`.
4. Unzip to get `app-release.apk` (any file manager on Android unzips).
5. Tap the APK to install — Android will ask you to allow "Install unknown apps" for your browser or file manager the first time.
6. Launch the app → grant SMS permission → tap the SMS icon on the Home tab to import the last 90 days of transactions.

Every push to `main` rebuilds and publishes a fresh APK as an artifact.

## Stack
- Flutter 3.29+ (Android only — iOS doesn't allow SMS read)
- SQLite (`sqflite`) for local storage
- `another_telephony` for SMS inbox + live listener
- `fl_chart` for charts
- `provider` for state

## Dev
```sh
flutter pub get
flutter test
flutter analyze
flutter build apk --release
```

## Project layout
```
lib/
  main.dart                 — app entry
  db/
    database.dart           — SQLite schema + queries
    models.dart             — Txn, Category, Budget, MerchantMap, PendingSms
  sms/
    parser.dart             — regex rules for bank/UPI SMS
    sms_service.dart        — inbox scan + live listener
  providers/
    app_state.dart          — ChangeNotifier
  screens/
    home_screen.dart        — dashboard + bottom nav
    add_txn_screen.dart     — new / edit transaction
    transactions_screen.dart — filtered list
    analytics_screen.dart   — charts + budgets
    review_screen.dart      — unparsed SMS queue
    settings_screen.dart    — categories + budgets
  widgets/
  utils/
```

## Extending the SMS parser
Edit `lib/sms/parser.dart`:
- `_knownSenderTokens` — add your bank's sender ID
- `_amountRe`, `_debitRe`, `_creditRe`, `_merchantRe` — tweak for new formats
- `_billDueRe`, `_dueDateRe` — credit-card statement detection

Add a test in `test/widget_test.dart` for any new SMS format before tweaking the regex.
