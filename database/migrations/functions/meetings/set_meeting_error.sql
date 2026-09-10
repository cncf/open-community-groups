-- set_meeting_error records a sync error and completes the target claim.
create or replace function set_meeting_error(
    p_error text,
    p_event_id uuid,
    p_meeting_id uuid,
    p_session_id uuid,
    p_sync_claimed_at timestamptz,
    p_sync_state_hash text
)
returns void as $$
begin
    -- Complete event or session claim when the worker still holds it
    if p_event_id is not null or p_session_id is not null then
        perform release_meeting_sync(
            p_event_id,
            p_session_id,
            p_sync_claimed_at,
            p_sync_state_hash,
            p_error
        );
    -- Orphan meeting case: no event/session to record error on, delete the row
    -- only when the worker still holds the claim
    elsif p_meeting_id is not null then
        delete from meeting
        where meeting_id = p_meeting_id
          and sync_claimed_at = p_sync_claimed_at;
    end if;
end;
$$ language plpgsql;
