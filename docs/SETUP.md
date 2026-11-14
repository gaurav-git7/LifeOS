# LifeOS — Setup Guide

What you need to create, where each value goes, and in what order.
Everything is free except Gemini API usage (pay-per-use, capped by you).

> **You can start without any accounts.** The backend runs locally on SQLite with a built-in
> fake assistant. Accounts are only needed to deploy and use real AI, push and email.

---

## Checklist

| # | Step | Needed for | Time |
|---|---|---|---|
| 0 | [Run the backend locally](#0-run-the-backend-locally-no-accounts) | Development | 5 min |
| 1 | [GitHub repository](#1-github-repository) | Deploys, CI, backups | 5 min |
| 2 | [Supabase (2 projects)](#2-supabase) | Database | 10 min |
| 3 | [Gemini API key + billing + budget alert](#3-gemini) | Real AI | 10 min |
| 4 | [Firebase (FCM)](#4-firebase-push-notifications) | Push notifications | 10 min |
| 5 | [Email: Resend or Gmail](#5-email) | Verification / reset emails | 5 min |
| 6 | [Render deploy](#6-render) | Hosting the API | 10 min |
| 7 | [Create your account](#7-create-your-account-first-user--admin) | Using the app | 2 min |
| 8 | [pg_cron schedules](#8-scheduled-jobs-pg_cron) | Reviews, summaries, events | 5 min |
| 9 | [Backup secrets](#9-weekly-backups) | Weekly encrypted backups | 5 min |

---

## 0. Run the backend locally (no accounts)

Requires Python 3.12+.

```powershell
cd C:\College_projects\LifeOS\backend
python -m venv .venv
.\.venv\Scripts\python -m pip install -e ".[dev]"
copy .env.example .env
.\.venv\Scripts\alembic upgrade head
.\.venv\Scripts\uvicorn app.main:app --reload
```

- API docs: http://localhost:8000/docs (disabled in production)
- Emails are printed to the terminal (`EMAIL_PROVIDER=console`)
- With no `GEMINI_API_KEY`, the assistant uses a deterministic fake so every flow works
- Tests: `.\.venv\Scripts\python -m pytest -q` · Lint: `.\.venv\Scripts\ruff check .`

To test against Postgres locally, put your **dev** Supabase URL in `backend/.env` (step 2).

---

## 1. GitHub repository

1. Create a **private** repository (e.g. `lifeos`).
2. From `C:\College_projects\LifeOS`:

   ```powershell
   git init
   git add .
   git commit -m "LifeOS: architecture, UI shell, backend"
   git branch -M main
   git remote add origin https://github.com/<you>/lifeos.git
   git push -u origin main
   ```

3. `.gitignore` already excludes `.env`, databases, `google-services.json` and keystores — double-check
   nothing secret is staged before pushing.

CI (`.github/workflows/backend-ci.yml`, `mobile-ci.yml`) runs automatically on push: lint + tests on SQLite
**and** on a real Postgres container, plus a migrate-up/down check.

---

## 2. Supabase

Create **two** free projects at [supabase.com](https://supabase.com): `lifeos-dev` and `lifeos-prod`.
Pick the region closest to you (e.g. **Mumbai / ap-south-1**). Save each database password in a password manager.

For each project:

1. **Connection string** → *Connect* → **Session pooler** (port 5432). It looks like
   `postgresql://postgres.<ref>:<password>@aws-0-<region>.pooler.supabase.com:5432/postgres`
2. For the app, change the scheme to `postgresql+asyncpg://` — that's your `DATABASE_URL`.
   (Keep the plain `postgresql://` form for backups in step 9.)
3. **Extensions** → *Database → Extensions* → enable **pg_cron** and **pg_net** (prod at least).
4. **Data API exposure**: the app's tables live in a schema called `app`, which Supabase does **not**
   expose by default. In *Project Settings → Data API → Exposed schemas*, make sure `app` is **not** listed.
   The mobile app never talks to Supabase directly — only to your API.

Tables are created by migrations automatically on every deploy (`alembic upgrade head` runs at container start).

> Free projects pause after about a week with no activity. Daily use (and the cron jobs in step 8) keep it awake.
> Free projects have no automatic backups — step 9 covers that.

---

## 3. Gemini

1. Go to [Google AI Studio](https://aistudio.google.com) → **Get API key** → create a key in a Google Cloud project.
2. **Turn on billing** for that project (Google Cloud Console → Billing). This moves you to the paid tier,
   where your prompts are not used to improve Google's products (check current terms).
3. **Budget alert**: Cloud Console → *Billing → Budgets & alerts* → create a budget (e.g. **₹200/month**)
   with email alerts at 50 %, 90 %, 100 %.
4. In-app cap: `AI_DAILY_BUDGET_USD` (default **$0.10/day**) — the API refuses AI calls past it and
   everything else keeps working. You can also set a personal cap in preferences (`ai_daily_budget_usd`).
5. **Check model IDs and prices** in the Gemini docs. Defaults are `gemini-2.5-flash-lite` / `gemini-2.5-flash` /
   `gemini-2.5-pro`; if newer models exist, set `GEMINI_MODEL_*` and update prices with
   `GEMINI_PRICES={"model-id":[input_per_1M, output_per_1M], ...}` so cost tracking stays accurate.

Value → `GEMINI_API_KEY`.

---

## 4. Firebase (push notifications)

1. [Firebase console](https://console.firebase.google.com) → *Add project* (you can select the same Google Cloud
   project as Gemini). Google Analytics is optional — you can turn it off.
2. **Add an Android app** with package name **`com.lifeos.lifeos`** (from
   `mobile/android/app/build.gradle.kts`). Download **`google-services.json`** → save it to
   `mobile/android/app/google-services.json` (git-ignored; used when the app is wired to FCM).
3. **Server key**: *Project settings → Service accounts → Generate new private key* → downloads a JSON file.
   Base64-encode it (one line) and use it as `FIREBASE_CREDENTIALS_JSON`:

   ```powershell
   [Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\path\to\service-account.json"))
   ```

   Never commit this file. Without it, the API still works — pushes are logged as `skipped`.

---

## 5. Email

Pick one:

**Resend (recommended)** — [resend.com](https://resend.com) → API key → `EMAIL_PROVIDER=resend`, `RESEND_API_KEY=…`.
Without your own domain, Resend sends from `onboarding@resend.dev` **only to your own account email** —
fine for a personal app. Add a domain later if you invite others.

**Gmail SMTP** — enable 2-step verification on your Google account → create an **App password** →
`EMAIL_PROVIDER=smtp`, `SMTP_USER=you@gmail.com`, `SMTP_PASSWORD=<app password>`, `EMAIL_FROM=LifeOS <you@gmail.com>`.

---

## 6. Render

1. [render.com](https://render.com) → sign in with GitHub → **New → Blueprint** → pick your repo.
   Render reads `render.yaml` and creates the free `lifeos-api` web service (Docker, `backend/`).
2. Fill the values Render asks for:

   | Variable | Value |
   |---|---|
   | `DATABASE_URL` | **prod** Supabase session-pooler URL with `postgresql+asyncpg://` |
   | `PUBLIC_APP_URL` | `https://<your-service>.onrender.com` (shown after the first deploy — update and redeploy) |
   | `GEMINI_API_KEY` | from step 3 |
   | `FIREBASE_CREDENTIALS_JSON` | base64 from step 4 |
   | `SMTP_USER` | your Gmail address (step 5, Gmail option — `render.yaml` uses Gmail SMTP) |
   | `SMTP_PASSWORD` | the 16-character Gmail **App password** (not your normal password) |
   | `EMAIL_FROM` | `LifeOS <your Gmail address>` |

   `JWT_SECRET` and `JOB_SECRET` are generated by Render automatically. `REGISTRATION_MODE=invite` is preset.
3. Deploy, then open `https://<your-service>.onrender.com/health` → `{"status":"ok","database":true}`.

> Free instances sleep after ~15 min idle and take ~30–60 s to wake. The keep-warm job in step 8 avoids this
> during your waking hours.

---

## 7. Create your account (first user = admin)

The **first** registration is always allowed (even in invite mode) and becomes **admin**. Production hides
`/docs`, so register with PowerShell:

```powershell
$api = "https://<your-service>.onrender.com/api/v1"
$body = @{ email="you@example.com"; password="<a long password>"; display_name="Gaurav"; timezone="Asia/Kolkata" } | ConvertTo-Json
Invoke-RestMethod -Method Post -Uri "$api/auth/register" -ContentType "application/json" -Body $body
```

Then click the verification link in your email. To let someone else in later:
`POST /api/v1/admin/invites` (as admin) returns a one-time invite code.

---

## 8. Scheduled jobs (pg_cron)

1. Open `supabase/cron.sql`, replace `<RENDER_URL>` and `<JOB_SECRET>` (copy it from Render → Environment).
2. Run it in the **prod** project's *SQL Editor*.
3. Check: `select jobname, schedule, active from cron.job;` and after a few minutes
   `select status, return_message from cron.job_run_details order by start_time desc limit 10;`

| Job | Every | Does |
|---|---|---|
| process-events | 5 min | Safety net for the event outbox |
| daily-summary | hour | Yesterday's stats, marks missed habits |
| daily-review | 15 min | Your daily review at/after your review time (default 21:00) |
| weekly-review | hour | Weekly report on your review day (default Sunday) |
| agent-jobs | 10 min | Restarts stuck AI jobs |
| cleanup | daily | Expires old proposals, tokens, logs |
| keep-warm (optional) | 10 min, daytime | Keeps the free Render instance awake |

---

## 9. Weekly backups

GitHub repo → *Settings → Secrets and variables → Actions* → add:

| Secret | Value |
|---|---|
| `SUPABASE_DB_URL` | **prod** session-pooler URL with plain `postgresql://` |
| `BACKUP_PASSPHRASE` | a long random passphrase — **store it in your password manager**, you need it to restore |

Run *Actions → weekly-db-backup → Run workflow* once to test. Backups are encrypted artifacts kept 90 days.
Restore: `gpg -d lifeos-<date>.sql.gz.gpg | gunzip | psql "<db url>"`.

---

## Environment variables (reference)

| Variable | Default | Notes |
|---|---|---|
| `APP_ENV` | development | `production` hides `/docs` |
| `DATABASE_URL` | local SQLite | Supabase: `postgresql+asyncpg://…` |
| `DB_SCHEMA` | app | Postgres schema for app tables |
| `JWT_SECRET` | dev default | **must** be set in production |
| `ACCESS_TOKEN_MINUTES` / `REFRESH_TOKEN_DAYS` | 15 / 30 | |
| `REGISTRATION_MODE` | open | `invite` in production |
| `PUBLIC_APP_URL` | localhost | used in email links |
| `JOB_SECRET` | dev default | header for `/internal/jobs/*` |
| `GEMINI_API_KEY` | empty | empty = fake assistant |
| `GEMINI_MODEL_LITE/DEFAULT/PRO` | 2.5 family | verify current IDs |
| `GEMINI_PRICES` | 2.5 prices | JSON, USD per 1M tokens |
| `AI_DAILY_BUDGET_USD` | 0.10 | per-user daily cap |
| `LLM_PROVIDER` | auto | `gemini` / `fake` to force |
| `FIREBASE_CREDENTIALS_JSON` | empty | raw or base64 JSON |
| `EMAIL_PROVIDER` | console | `resend` / `smtp` |
| `EMAIL_FROM`, `RESEND_API_KEY`, `SMTP_*` | | |
| `CORS_ORIGINS` | none | not needed for the mobile app |
| `RATE_LIMIT_ENABLED` | true | |

---

## What's next

The mobile app still runs on its own sample UI. Connecting it to this API (login/register screens, Dio client,
Drift cache, FCM token registration) is the next phase — see ARCHITECTURE.md §21.
