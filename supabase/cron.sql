-- LifeOS scheduled jobs (ARCHITECTURE.md §11.3).
-- Run ONCE in Supabase → SQL Editor, after the API is deployed on Render.
-- Replace the two placeholders below first:
--   <RENDER_URL>  e.g. https://lifeos-api.onrender.com
--   <JOB_SECRET>  the JOB_SECRET value from Render → Environment

-- 1) Extensions (also enable them in Dashboard → Database → Extensions if this fails)
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- 2) Store the URL and secret in Supabase Vault (encrypted), not in job SQL
select vault.create_secret('<RENDER_URL>', 'lifeos_api_url');
select vault.create_secret('<JOB_SECRET>', 'lifeos_job_secret');

-- 3) Helper that calls an internal job endpoint
create or replace function public.lifeos_call_job(path text)
returns bigint
language sql
security definer
as $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'lifeos_api_url') || path,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'X-Job-Secret', (select decrypted_secret from vault.decrypted_secrets where name = 'lifeos_job_secret')
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 60000
  );
$$;
revoke all on function public.lifeos_call_job(text) from public, anon, authenticated;

-- 4) Schedules (UTC). Jobs are catch-up style: running more often is harmless.
select cron.schedule('lifeos-process-events', '*/5 * * * *',  $$select public.lifeos_call_job('/internal/jobs/process-events')$$);
select cron.schedule('lifeos-daily-summary',  '5 * * * *',    $$select public.lifeos_call_job('/internal/jobs/daily-summary')$$);
select cron.schedule('lifeos-daily-review',   '*/15 * * * *', $$select public.lifeos_call_job('/internal/jobs/daily-review')$$);
select cron.schedule('lifeos-weekly-review',  '20 * * * *',   $$select public.lifeos_call_job('/internal/jobs/weekly-review')$$);
select cron.schedule('lifeos-agent-jobs',     '*/10 * * * *', $$select public.lifeos_call_job('/internal/jobs/run-agent-jobs')$$);
select cron.schedule('lifeos-cleanup',        '0 3 * * *',    $$select public.lifeos_call_job('/internal/jobs/cleanup')$$);

-- Optional keep-warm while you're awake (01:00–18:59 UTC ≈ 06:30–00:30 IST).
-- Keeps Render's free instance from sleeping during the day (~560 of the 750 free hours/month).
select cron.schedule('lifeos-keep-warm', '*/10 1-18 * * *',
  $$select net.http_get(url := (select decrypted_secret from vault.decrypted_secrets where name = 'lifeos_api_url') || '/health')$$);

-- Check:   select jobname, schedule, active from cron.job;
-- History: select * from cron.job_run_details order by start_time desc limit 20;
-- Remove:  select cron.unschedule('lifeos-keep-warm');
