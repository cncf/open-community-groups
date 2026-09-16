-- E2E seed data for the Playwright suite.
--
-- The catalog is split into ordered parts; each part depends only on rows created by earlier
-- parts. Load through `just db-load-tests-e2e-data` (psql -X -v ON_ERROR_STOP=1 -f e2e.sql).
begin;

-- Relative timestamps (date_trunc + interval) must resolve identically on every machine, so pin
-- the session timezone to UTC for the whole load.
set local timezone to 'UTC';

\ir e2e/00_site.sql
\ir e2e/10_catalog.sql
\ir e2e/20_groups.sql
\ir e2e/30_events.sql
\ir e2e/40_users_badges.sql
\ir e2e/50_membership_cfs.sql
\ir e2e/60_enrollment.sql
\ir e2e/70_payments.sql
\ir e2e/80_meetings.sql
\ir e2e/90_audit_sessions.sql

commit;
