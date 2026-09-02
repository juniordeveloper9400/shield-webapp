# Firebase Phone Auth — finishing setup

The app code is done. Member sign-in (`AuthService`) runs Firebase Phone Auth
only — there is no demo or offline fallback, so a `Firebase.initializeApp()`
failure at launch is fatal by design (see `lib/main.dart`). The agent
registration screen keeps a separate placeholder `123456` step; that is
unrelated to member sign-in.

**Project:** `shield-zabnix`
**Android package / iOS bundle id:** `com.zabnix.shield`

## Status

- [x] `android/app/google-services.json` is in place (project `shield-zabnix`,
      app `1:1086152719549:android:b63fc70829f7da89da0bd4`). Verified with
      `./gradlew :app:processDebugGoogleServices` → BUILD SUCCESSFUL.
- [x] Gradle plugin wired (applies automatically now that the file exists).
- [x] `INTERNET` permission added to the release manifest.
- [x] **Debug SHA added to the console** — SHA-1
      `73:DE:3A:26:2B:D5:12:25:1A:C2:7B:25:35:7E:EB:07:9C:64:26:B9` and its
      SHA-256 are registered on the `com.zabnix.shield` Android app
      (2026-08-31). `android/app/google-services.json` carries the matching
      SHA-1 in its `oauth_client.certificate_hash`.
- [x] **Phone provider enabled** — Authentication → Sign-in method → Phone →
      Enabled (2026-08-31). Note the console's default cap of 1000 sent
      SMS/day on billed projects; raise it via Identity Platform if needed.
- [ ] iOS: `GoogleService-Info.plist` + APNs key (only if you ship iOS).

Do **not** add the Admin SDK service account
(`firebase-adminsdk-…@shield-zabnix.iam.gserviceaccount.com`) or its JSON key to
this app — it is a server-only credential.

---

## Option A — FlutterFire CLI (recommended, does Android + iOS)

```bash
firebase login
dart pub global activate flutterfire_cli
flutterfire configure --project=shield-zabnix
```

This writes `lib/firebase_options.dart`, `android/app/google-services.json`,
`ios/Runner/GoogleService-Info.plist`, and the iOS pod wiring. The Android
Gradle plugin is already wired in this repo (`android/settings.gradle.kts` has
it on the classpath; `android/app/build.gradle.kts` applies it automatically as
soon as `google-services.json` exists), so `flutterfire configure` will leave it
alone.

Optionally switch `main.dart` to the generated options:

```dart
import 'firebase_options.dart';
// ...
await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
```

The current bare `Firebase.initializeApp()` also works once the native config
files above are present.

## Option B — manual, Android only

1. Firebase console → **Project settings → Add app → Android**, package
   `com.zabnix.shield`.
2. Download **`google-services.json`** into `android/app/`.
3. `main.dart` already calls `Firebase.initializeApp()` — nothing to change.

---

## Console steps (needed for both options)

1. **Authentication → Sign-in method → Phone → Enable.**
2. **Project settings → your Android app → Add fingerprint**, add both
   (debug keystore, `C:\Users\User\.android\debug.keystore`):

   | Type | Value |
   |------|-------|
   | SHA-1 | `73:DE:3A:26:2B:D5:12:25:1A:C2:7B:25:35:7E:EB:07:9C:64:26:B9` |
   | SHA-256 | `B3:E8:DF:E2:9B:73:AD:7C:E7:9E:E1:93:5F:50:6B:00:88:38:1D:4A:22:EA:B3:C6:22:2F:96:42:D7:F6:98:0D` |

   Regenerate any time: `cd android && ./gradlew signingReport`.
   Add your **release** keystore's fingerprints too before shipping — the app
   currently signs release with the debug key, so the values above cover it for
   now.
3. Re-download `google-services.json` after adding fingerprints (it embeds
   them).
4. **iOS only:** Project settings → Cloud Messaging → upload an **APNs auth
   key**. Phone Auth silent-push verification needs it.
5. If SMS volume will be high, enable **Blaze billing** — the Spark plan caps
   Phone Auth SMS.

---

## Web (Vercel deploy)

Phone Auth in a browser runs a **reCAPTCHA** check before any SMS is sent, and
Firebase only runs it on origins it trusts. A fresh Vercel deployment is not on
that list, so `verifyPhoneNumber` / `signInWithPhoneNumber` never completes and
the app shows *"Verification timed out before the code was sent."*

1. Firebase console → **Authentication → Settings → Authorized domains → Add
   domain**. Add every origin the app is actually served from:
   - the production domain (e.g. `shield-webapp.vercel.app` or a custom domain);
   - any preview domain you test on (`shield-webapp-git-<branch>-<team>.vercel.app`,
     `shield-webapp-<hash>.vercel.app`). Wildcards are **not** supported — add
     each exact host, or pin testing to one stable alias.
   `localhost` is authorized by default for `flutter run -d chrome`.
2. If the **web API key** (`firebase_options.dart` → `web.apiKey`) has
   *Application restrictions → HTTP referrers* set in Google Cloud console, add
   the same domains there (`https://shield-webapp.vercel.app/*`).
3. Phone provider must be enabled and, for real numbers, the project on
   **Blaze** — same as Android. Test numbers under *Phone numbers for testing*
   skip both reCAPTCHA and SMS and are the quickest way to confirm the wiring.

## Verify

```bash
flutter run
```

- Real number → real SMS → 6-digit code → signed in.
- The "Demo mode · the code is 123456" hint disappears automatically once
  Firebase initialises (it is gated on `AuthService.instance.isDemo`).
- Emulator / no SIM: add a **test phone number + code** under Authentication →
  Sign-in method → Phone → *Phone numbers for testing*.

## Troubleshooting

| Symptom | Cause |
|---|---|
| Still shows demo code `123456` on a real build | `Firebase.initializeApp()` threw — `google-services.json` missing or malformed. Check `flutter run` logs for `Firebase not configured`. |
| `This app is not authorized to use Firebase Authentication` / error 17028 | SHA-1/SHA-256 not added, or `google-services.json` not re-downloaded after adding them. |
| Real device build ignores Firebase | `google-services.json` not in `android/app/` — the Gradle plugin only applies when that file exists. |
| SMS never arrives, no error | Phone provider not enabled, or Spark SMS quota hit, or number needs to be a test number on an emulator. |
| Web: "Verification timed out before the code was sent" + a broken reCAPTCHA image | The deploy origin is not in **Authentication → Settings → Authorized domains** (or the web API key's HTTP-referrer list). Add the exact Vercel host. |
