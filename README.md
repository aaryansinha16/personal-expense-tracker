# Personal Expense Tracker

A local-first Android expense tracker built with Flutter. Tracks income and expenses, auto-detects transactions from bank/UPI SMS **and** from merchant emails, and gives you analytics + a daily budget — all stored locally on your device.

![Build APK](https://github.com/aaryansinha16/personal-expense-tracker/actions/workflows/build-apk.yml/badge.svg)

## Features
- **SMS auto-import** — HDFC, SBI, ICICI, Axis, Kotak, PhonePe, GPay, Paytm, CRED, Amazon Pay, etc.
- **Email import** — share an email from any app, paste email text, **or** connect Gmail for auto-sync.
- **Daily budget engine** — set monthly income, savings target, and fixed expenses; the app tells you how much you can safely spend today.
- **Monthly budgets** per category with over-limit warnings.
- **Analytics** — week / month / year, pie by category, daily-spend line chart, progress bars.
- **Smart insights** — under-budget streak, weekend-vs-weekday, top category, biggest day, no-spend days.
- **Review queue** teaches the app: categorize once, future SMS/emails from the same merchant auto-categorize.
- **Everything is local.** No cloud DB, no analytics, no telemetry.

## Install on your phone (no USB needed)
1. Go to the **[Actions tab](https://github.com/aaryansinha16/personal-expense-tracker/actions)** of this repo on your phone.
2. Open the latest successful **Build APK** run.
3. Under **Artifacts**, download `expense-tracker-apk.zip`.
4. Unzip → tap `app-release.apk` → allow install-from-unknown-apps when prompted.
5. Launch → grant SMS permission → Settings → SMS sync → pick a scan range.

## Setup Gmail auto-sync (optional)
Two one-time setups. The share-sheet and manual-paste email flows work without any of this.

### 1. Stable release keystore for CI
Gmail OAuth rejects APKs whose signing SHA-1 changes each build. Fix: sign CI builds with a fixed key.

```sh
# Generate the keystore once (anywhere — the file never leaves your machine).
keytool -genkey -v -keystore release.keystore -alias expense-tracker \
  -keyalg RSA -keysize 2048 -validity 36500

# Print the SHA-1 (used in the Google Cloud step below).
keytool -list -v -keystore release.keystore -alias expense-tracker | grep SHA1

# Base64 encode it for GitHub Secrets.
base64 -i release.keystore | pbcopy   # macOS; Linux: base64 release.keystore
```

Add these **repository secrets** (Settings → Secrets and variables → Actions):
- `RELEASE_KEYSTORE_BASE64` — the base64 string from above.
- `RELEASE_STORE_PASSWORD` — the keystore password you just set.
- `RELEASE_KEY_ALIAS` — `expense-tracker`.
- `RELEASE_KEY_PASSWORD` — the key password you just set.

Next push to `main` will produce an APK signed with your stable key.

### 2. Google Cloud Console OAuth client
1. [console.cloud.google.com](https://console.cloud.google.com) → create a project.
2. **Enable APIs & Services** → search *Gmail API* → enable.
3. **OAuth consent screen** → User type: *External* → fill name/email → scopes: add `https://www.googleapis.com/auth/gmail.readonly` → test users: add your Google account.
4. **Credentials → Create credentials → OAuth client ID** → *Android*:
   - Package name: `com.aaryan.expense_tracker`
   - SHA-1: the fingerprint you printed in step 1.
5. Save. No file to paste into the app — Android matches by package name + SHA-1 automatically.

After the next CI build, open the app → Settings → **Gmail auto-sync** → Connect Gmail.

## Stack
- Flutter 3.29+ (Android only — iOS doesn't allow SMS read)
- SQLite (`sqflite`) for local storage
- `another_telephony` for SMS inbox + live listener
- `receive_sharing_intent` for share-sheet email import
- `google_sign_in` + `googleapis/gmail` for Gmail auto-sync
- `fl_chart` for charts
- `provider` for state

## Dev
```sh
flutter pub get
flutter test
flutter analyze
flutter build apk --release --no-tree-shake-icons
```

## Project layout
```
lib/
  main.dart                  — app entry
  db/
    database.dart            — SQLite schema + queries
    models.dart              — Txn, Category, Budget, MerchantMap, PendingSms, RecurringExpense
  sms/
    parser.dart              — regex rules for bank/UPI SMS
    sms_service.dart         — inbox scan + live listener
  email/
    parser.dart              — regex rules for merchant emails
    sender_rules.dart        — known-sender → display-name + category hint
    gmail_service.dart       — OAuth sign-in + Gmail API polling
  services/
    share_receiver.dart      — Android SEND intent listener
    monthly_setup.dart       — income / savings / recurring expenses
    daily_budget.dart        — daily-budget engine
    insights.dart            — streaks, patterns, top-category
  providers/
    app_state.dart           — ChangeNotifier
  screens/
    home_screen.dart         — dashboard + bottom nav
    add_txn_screen.dart      — new / edit transaction
    transactions_screen.dart — filtered list
    analytics_screen.dart    — charts + budgets + insights
    review_screen.dart       — unparsed SMS queue
    settings_screen.dart     — categories + budgets + sync
    sms_sync_screen.dart     — SMS scan + reset
    email_sync_screen.dart   — Gmail connect + scan + reset
    import_email_screen.dart — paste / share-received email parse
    budget_setup_screen.dart — monthly income / savings / fixed expenses
  widgets/
  utils/
```
