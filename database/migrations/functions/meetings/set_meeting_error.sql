-- set_meeting_error records a sync error and completes the target claim.
drop function if exists set_meeting_error(text, uuid, uuid, uuid);
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
    -- Event meeting case
    if p_event_id is not null then
        -- Complete only the claim for the same owner state
        update event
        set
            meeting_error = case
                when current_state.sync_state_hash = p_sync_state_hash then p_error
                else meeting_error
            end,
            meeting_in_sync = current_state.sync_state_hash = p_sync_state_hash,
            meeting_provider_host_user = null,
            meeting_sync_claimed_at = null
        from (
            select get_event_meeting_sync_state_hash(p_event_id) as sync_state_hash
        ) current_state
        where event_id = p_event_id
          and meeting_sync_claimed_at = p_sync_claimed_at;
    -- Session meeting case
    elsif p_session_id is not null then
        -- Complete only the claim for the same owner state
        update session
        set
            meeting_error = case
                when current_state.sync_state_hash = p_sync_state_hash then p_error
                else meeting_error
            end,
            meeting_in_sync = current_state.sync_state_hash = p_sync_state_hash,
            meeting_provider_host_user = null,
            meeting_sync_claimed_at = null
        from (
            select get_session_meeting_sync_state_hash(p_session_id) as sync_state_hash
        ) current_state
        where session_id = p_session_id
          and meeting_sync_claimed_at = p_sync_claimed_at;
    -- Orphan meeting case: no event/session to record error on, delete the row
    elsif p_meeting_id is not null then
        delete from meeting
        where meeting_id = p_meeting_id;
    end if;
end;
$$ language plpgsql;
