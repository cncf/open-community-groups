-- release_meeting_sync_claim releases a retryable meeting sync claim.
drop function if exists release_meeting_sync_claim(uuid, uuid, uuid);
create or replace function release_meeting_sync_claim(
    p_event_id uuid,
    p_meeting_id uuid,
    p_session_id uuid,
    p_sync_claimed_at timestamptz
) returns void as $$
begin
    -- Event meeting case
    if p_event_id is not null then
        update event
        set
            meeting_provider_host_user = null,
            meeting_sync_claimed_at = null
        where event_id = p_event_id
          and meeting_in_sync = false
          and meeting_sync_claimed_at = p_sync_claimed_at;
    -- Session meeting case
    elsif p_session_id is not null then
        update session
        set
            meeting_provider_host_user = null,
            meeting_sync_claimed_at = null
        where session_id = p_session_id
          and meeting_in_sync = false
          and meeting_sync_claimed_at = p_sync_claimed_at;
    -- Orphan meeting case
    elsif p_meeting_id is not null then
        update meeting
        set
            sync_claimed_at = null,
            updated_at = current_timestamp
        where meeting_id = p_meeting_id
          and sync_claimed_at = p_sync_claimed_at;
    end if;
end;
$$ language plpgsql;
