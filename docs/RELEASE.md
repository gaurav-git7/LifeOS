# Releasing the Android app

Release APKs are signed with **your** key. Android only installs an update over an
existing app if both are signed with the same key, so create it once and keep it safe.
Lose it and you'll have to uninstall LifeOS (and its local cache) to install a new build.
Your data is safe either way, because it lives on the server.

## 1. Create the signing key (once)

`keytool` comes with Java. Run this from the `mobile/android` folder and answer the questions
(name can be anything; pick a strong password and save it in your password manager):

```bash
keytool -genkey -v -keystore lifeos-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias lifeos
```

Then create `mobile/android/key.properties` (already git-ignored, never commit it):

```properties
storeFile=../lifeos-release.jks
storePassword=YOUR_PASSWORD
keyAlias=lifeos
keyPassword=YOUR_PASSWORD
```

`storeFile` is relative to `mobile/android/app`. `*.jks` and `key.properties` are both in
`mobile/android/.gitignore`. Check with `git status` that neither shows up.

**Back up** `lifeos-release.jks` and the password somewhere other than this laptop
(e.g. Google Drive + password manager).

## 2. Build on your laptop

```bash
cd mobile
flutter build apk --release --split-per-abi --target-platform android-arm64
```

The APK is `mobile/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` (~23 MB).
Install it with the phone on USB (plain `flutter install --release` looks for the universal
`app-release.apk`, which this command doesn't build):

```bash
flutter install --use-application-binary build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

Or copy the APK to the phone and open it (allow "Install unknown apps" for your file manager once).

> If you installed a **debug** build before (`flutter run`), uninstall it first: Android refuses
> to replace an app signed with a different key.

## 3. Let GitHub build releases (optional, nice for the resume)

Add four secrets in GitHub → repo → **Settings → Secrets and variables → Actions → New repository secret**:

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | the `.jks` file as base64 (command below) |
| `ANDROID_KEYSTORE_PASSWORD` | your store password |
| `ANDROID_KEY_ALIAS` | `lifeos` |
| `ANDROID_KEY_PASSWORD` | your key password |

Base64 of the keystore (PowerShell, copies it to the clipboard):

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("mobile\android\lifeos-release.jks")) | Set-Clipboard
```

Then tag a version and push the tag:

```bash
git tag v0.1.0
git push origin v0.1.0
```

The `release-apk` workflow tests, builds `LifeOS-0.1.0.apk` (all phones) and
`LifeOS-0.1.0-arm64.apk` (smaller), and attaches both to a GitHub Release.
Download it on the phone from the Releases page and install.

For the next version bump the tag (`v0.1.1`, `v0.2.0`, …). The build number comes from the
workflow run, so every release installs over the previous one.

## 4. Server push + "update available" notifications

Push comes from Firebase Cloud Messaging (free on Firebase's Spark plan).

1. **Server key (Render).** Firebase console → Project settings → Service accounts → *Generate new private
   key*. On Render → lifeos-api → Environment, set `FIREBASE_CREDENTIALS_JSON` to the whole JSON file
   (or its base64). Never commit this file.
2. **App config (GitHub).** The APK needs `mobile/android/app/google-services.json` (you already have it
   locally; it's git-ignored). Add it as a secret so GitHub builds include push:
   ```powershell
   [Convert]::ToBase64String([IO.File]::ReadAllBytes("mobile\android\app\google-services.json")) | Set-Clipboard
   ```
   → secret `GOOGLE_SERVICES_JSON_BASE64`.
3. **Update notification.** Add two more secrets:
   `LIFEOS_API_URL` = `https://lifeos-api-xxrp.onrender.com` (no `/api/v1`) and `LIFEOS_JOB_SECRET` = the
   same `JOB_SECRET` as on Render. After each `v*` release, phones on an older version get
   "LifeOS x.y.z is ready"; tapping it opens the release page.

## 5. Crash reports and feedback (free)

The app sends crashes (release builds) and Settings → *Send feedback* to your own server, table
`app.client_reports`. You get a push for each feedback. Read them in Supabase → Table editor, or:

```sql
select created_at, kind, count, app_version, message from app.client_reports order by last_seen_at desc limit 50;
```

Mark one handled with `update app.client_reports set status = 'fixed' where id = '...';`

## 6. Staying at $0

| Service | Check |
|---|---|
| Render | `render.yaml` uses `plan: free`. In the dashboard → *Billing*, the service shows **Free**; don't add paid add-ons (disks, bigger instance). Free services are suspended, not billed, if they hit a limit. Removing the card under Billing makes charges impossible. |
| Supabase | Organization plan **Free** (no card needed). |
| Firebase | Plan **Spark** (no billing account). Never upgrade to Blaze. |
| Gemini | Free tier unless billing is enabled on the Google project (see AI Studio → API keys → plan). |

## Why the assistant says it can't reach the AI

The server now tells you the reason; as the admin you also see the raw error under `[admin]`.

| Kind | Fix |
|---|---|
| `quota` | Free-tier limit reached. Wait, or enable billing on the Google project. |
| `key` | `GEMINI_API_KEY` on Render is wrong or restricted. |
| `model` | Google retired the model name: set `GEMINI_MODEL_LITE` / `GEMINI_MODEL_DEFAULT` on Render to current ones listed in AI Studio. |

The last errors are also in Supabase: `select created_at, model, status, error from app.llm_calls order by created_at desc limit 10;`

## Reminders on the phone

Reminders are scheduled on the phone itself: no server and no Firebase needed, and they work offline.

| What | When |
|---|---|
| Task with a time | 15 min before |
| Habit with a reminder time | that time, on days it isn't done yet |
| Focus / study block | 5 min before |
| Morning plan | 8:00, if something is due |
| Topics to revise | 18:00 |
| Daily review | your review time (Settings) |

Task reminders have **Done / Snooze 15 min / Tomorrow** buttons; habit reminders **Done / Later**.
Pressed while the app is closed, they're applied the next time LifeOS opens. Habits only remind on the
days they're scheduled (every day, picked days, every N days, or N× a week).

Quiet hours (22:30–07:00) hold back the summaries but not times you picked yourself.

After installing:

1. Allow notifications when Android asks (Settings → *Notifications* in LifeOS if you missed it).
2. Settings → **On-the-minute reminders** → allow "Alarms & reminders". Without it Android may
   deliver a reminder a few minutes late.
3. Samsung only: Android Settings → Apps → LifeOS → Battery → **Unrestricted**. Otherwise One UI
   can delay or drop reminders when the phone is idle.
4. Settings → **Send a test notification** to check.

## Friends, groups and the home-screen widget

- **Friends:** Home → 👥 → share your friend code; a friend adds it and you accept. Friends only see
  habits you switch to *Share with friends* (habit details): the name, streak and whether it's done
  today. Tasks, goals, journal, mood and the assistant are never shared. Cheer (🔥 👏 💪) or nudge
  (once a day) from their card; both send a push.
- **Groups:** Friends → Groups → *New group*, add a habit (any schedule), share the code. Everyone
  checks in on their own phone; group habits also show in Plan → Habits. Group streak: everyone does
  it, with one free miss per week for the group ("N× a week" habits count weeks where everyone hit N).
  When the whole group finishes a day, everyone gets a 🎉 push.
- **Widget:** long-press the home screen → Widgets → LifeOS → *Today*. It shows today's rings and top
  3 tasks, updates when your data changes, opens the app on tap, and **+** opens quick add.
