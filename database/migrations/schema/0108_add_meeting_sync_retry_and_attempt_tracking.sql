-- Adds meeting sync retry backoff and create-attempt tracking columns.

-- Bound lock waits and backfill duration so the migration fails instead of
-- stalling the app.
set local lock_timeout = '5s';
set local statement_timeout = '10min';

-- Add create-attempt, sticky host, and retry backoff tracking to event rows
alter table event
    add column meeting_create_attempted_at timestamptz,
    add column meeting_last_provider_host_user text check (btrim(meeting_last_provider_host_user) <> ''),
    add column meeting_next_sync_at timestamptz,
    add column meeting_sync_attempts integer default 0 not null check (meeting_sync_attempts >= 0);

-- Add create-attempt, sticky host, and retry backoff tracking to session rows
alter table session
    add column meeting_create_attempted_at timestamptz,
    add column meeting_last_provider_host_user text check (btrim(meeting_last_provider_host_user) <> ''),
    add column meeting_next_sync_at timestamptz,
    add column meeting_sync_attempts integer default 0 not null check (meeting_sync_attempts >= 0);

-- Add retry backoff tracking to orphan meeting delete rows
alter table meeting
    add column next_sync_at timestamptz,
    add column sync_attempts integer default 0 not null check (sync_attempts >= 0);

-- Backfill create-attempt and sticky host tracking for existing events that
-- have ever entered automatic meeting sync without a stored meeting row, or
-- hold an active host reservation, so upgraded workers scan before creating
-- instead of risking duplicate provider meetings.
update event e
set
    meeting_create_attempted_at = case
        when not exists (
                 select 1
                 from meeting m
                 where m.event_id = e.event_id
             )
             and (
                 e.meeting_requested = true
                 or e.meeting_error is not null
                 or e.meeting_in_sync is not null
                 or e.meeting_provider_host_user is not null
                 or e.meeting_sync_claimed_at is not null
             )
        then current_timestamp
        else e.meeting_create_attempted_at
    end,
    meeting_last_provider_host_user = coalesce(
        e.meeting_provider_host_user,
        e.meeting_last_provider_host_user
    )
where (
          not exists (
              select 1
              from meeting m
              where m.event_id = e.event_id
          )
          and (
              e.meeting_requested = true
              or e.meeting_error is not null
              or e.meeting_in_sync is not null
              or e.meeting_provider_host_user is not null
              or e.meeting_sync_claimed_at is not null
          )
      )
   or e.meeting_provider_host_user is not null;

-- Backfill create-attempt and sticky host tracking for existing sessions with
-- the same upgrade safety rule, bypassing the session bounds trigger so
-- supported legacy out-of-bounds sessions do not abort the migration.
do $$
begin
    -- Avoid failing this metadata backfill on pre-existing legacy session bounds
    perform set_config('ocg.skip_session_bounds_check', 'on', true);

    -- Backfill session create-attempt and sticky host tracking
    update session s
    set
        meeting_create_attempted_at = case
            when not exists (
                     select 1
                     from meeting m
                     where m.session_id = s.session_id
                 )
                 and (
                     s.meeting_requested = true
                     or s.meeting_error is not null
                     or s.meeting_in_sync is not null
                     or s.meeting_provider_host_user is not null
                     or s.meeting_sync_claimed_at is not null
                 )
            then current_timestamp
            else s.meeting_create_attempted_at
        end,
        meeting_last_provider_host_user = coalesce(
            s.meeting_provider_host_user,
            s.meeting_last_provider_host_user
        )
    where (
              not exists (
                  select 1
                  from meeting m
                  where m.session_id = s.session_id
              )
              and (
                  s.meeting_requested = true
                  or s.meeting_error is not null
                  or s.meeting_in_sync is not null
                  or s.meeting_provider_host_user is not null
                  or s.meeting_sync_claimed_at is not null
              )
          )
       or s.meeting_provider_host_user is not null;
end;
$$;
