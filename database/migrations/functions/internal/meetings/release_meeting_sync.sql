-- Completes an event or session meeting sync claim held by a worker. The
-- claim is released only when p_sync_claimed_at still matches; the row is
-- marked in sync when the state hash the worker synchronized is still
-- current, and p_error (null on success) replaces the meeting error in that
-- case. Returns whether the claim was still held.
create or replace function release_meeting_sync(
    p_event_id uuid,
    p_session_id uuid,
    p_sync_claimed_at timestamptz,
    p_sync_state_hash text,
    p_error text
)
returns boolean as $$
declare
    v_claim_held boolean := false;
begin
    if p_event_id is not null then
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
        v_claim_held := found;
    elsif p_session_id is not null then
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
        v_claim_held := found;
    end if;

    return v_claim_held;
end;
$$ language plpgsql;
