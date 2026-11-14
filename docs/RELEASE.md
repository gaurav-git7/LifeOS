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

Quiet hours (22:30–07:00) hold back the summaries but not times you picked yourself.

After installing:

1. Allow notifications when Android asks (Settings → *Notifications* in LifeOS if you missed it).
2. Settings → **On-the-minute reminders** → allow "Alarms & reminders". Without it Android may
   deliver a reminder a few minutes late.
3. Samsung only: Android Settings → Apps → LifeOS → Battery → **Unrestricted**. Otherwise One UI
   can delay or drop reminders when the phone is idle.
4. Settings → **Send a test notification** to check.
