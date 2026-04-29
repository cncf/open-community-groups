-- Add meeting processing claim tracking and reset claim function signatures

drop function if exists add_meeting(text, text, text, text, text, uuid, uuid);
drop function if exists assign_zoom_host_user(uuid, uuid, text[], integer, timestamptz, timestamptz);
drop function if exists claim_meeting_for_auto_end();
drop function if exists claim_meeting_out_of_sync();
drop function if exists delete_meeting(uuid, uuid, uuid);
drop function if exists release_meeting_sync_claim(uuid, uuid, uuid);
drop function if exists set_meeting_error(text, uuid, uuid, uuid);
drop function if exists update_meeting(uuid, text, text, text, uuid, uuid);

alter table event
    add column meeting_provider_host_user text check (btrim(meeting_provider_host_user) <> ''),
    add column meeting_sync_claimed_at timestamptz;

alter table session
    add column meeting_provider_host_user text check (btrim(meeting_provider_host_user) <> ''),
    add column meeting_sync_claimed_at timestamptz;

alter table meeting
    add column auto_end_check_claimed_at timestamptz,
    add column sync_claimed_at timestamptz;

create index event_meeting_sync_claim_idx on event (meeting_sync_claimed_at)
    where meeting_in_sync = false;

create index meeting_auto_end_check_claim_idx on meeting (auto_end_check_claimed_at)
    where auto_end_check_at is null;

create index meeting_sync_claim_idx on meeting (sync_claimed_at)
    where event_id is null and session_id is null;

create index session_meeting_sync_claim_idx on session (meeting_sync_claimed_at)
    where meeting_in_sync = false;
