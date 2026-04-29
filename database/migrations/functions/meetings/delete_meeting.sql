-- delete_meeting deletes a meeting and completes the event/session claim.
drop function if exists delete_meeting(uuid, uuid, uuid);
create or replace function delete_meeting(
    p_meeting_id uuid,
    p_event_id uuid,
    p_session_id uuid,
    p_sync_claimed_at timestamptz,
    p_sync_state_hash text
) returns void as $$
begin
    -- Delete meeting (if one exists)
    if p_meeting_id is not null then
        delete from meeting where meeting_id = p_meeting_id;
    end if;

    -- Complete event claim when the owner state did not change
    if p_event_id is not null then
        update event
        set
            meeting_error = case
                when current_state.sync_state_hash = p_sync_state_hash then null
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
    end if;

    -- Complete session claim when the owner state did not change
    if p_session_id is not null then
        update session
        set
            meeting_error = case
                when current_state.sync_state_hash = p_sync_state_hash then null
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
    end if;
end;
$$ language plpgsql;
