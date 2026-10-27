-- Completes an event or session meeting sync claim held by a worker. The
-- claim is released only when p_sync_claimed_at still matches, and the result
-- reports whether the claim was still held. The claimed row is locked before
-- its current state hash is read, so the hash reflects writes committed while
-- waiting for the lock. When the hash still matches p_sync_state_hash, the
-- worker synchronized the current state: p_error (null on success) replaces
-- the meeting error and the row is marked in sync. Otherwise, or when
-- p_sync_state_hash is missing, the synchronized state cannot be confirmed:
-- the earlier error is kept and the row is marked out of sync so a later
-- claim synchronizes it. Claims only take rows out of sync, so a null
-- meeting_in_sync at release is a keep decision an update recorded during the
-- claim; it stays null whether or not the hash matches, so the kept meeting
-- is never claimed for deletion afterwards.
create or replace function release_meeting_sync(
    p_event_id uuid,
    p_session_id uuid,
    p_sync_claimed_at timestamptz,
    p_sync_state_hash text,
    p_error text
)
returns boolean as $$
declare
    v_meeting_in_sync boolean;
    v_state_unchanged boolean;
begin
    -- Release an event claim
    if p_event_id is not null then
        -- Lock the event while the worker still holds its claim
        select e.meeting_in_sync
        into v_meeting_in_sync
        from event e
        where e.event_id = p_event_id
        and e.meeting_sync_claimed_at = p_sync_claimed_at
        for update of e;

        -- Report a claim that is no longer held
        if not found then
            return false;
        end if;

        -- Compare the synchronized state with the locked event state
        v_state_unchanged := get_event_meeting_sync_state_hash(p_event_id) is not distinct from p_sync_state_hash;

        -- Record the outcome and release the claim
        update event
        set
            meeting_error = case
                -- Record the worker outcome for the current state
                when v_state_unchanged then p_error
                -- Keep the earlier error for a state the worker did not see
                else meeting_error
            end,
            meeting_in_sync = case
                -- Keep a meeting marked keep during the claim
                when v_meeting_in_sync is null then null
                -- Mark the event in sync only when its state is unchanged
                else v_state_unchanged
            end,
            meeting_provider_host_user = null,
            meeting_sync_claimed_at = null
        where event_id = p_event_id;

    -- Release a session claim
    elsif p_session_id is not null then
        -- Lock the session while the worker still holds its claim
        select s.meeting_in_sync
        into v_meeting_in_sync
        from session s
        where s.session_id = p_session_id
        and s.meeting_sync_claimed_at = p_sync_claimed_at
        for update of s;

        -- Report a claim that is no longer held
        if not found then
            return false;
        end if;

        -- Compare the synchronized state with the locked session state
        v_state_unchanged := get_session_meeting_sync_state_hash(p_session_id) is not distinct from p_sync_state_hash;

        -- Record the outcome and release the claim
        update session
        set
            meeting_error = case
                -- Record the worker outcome for the current state
                when v_state_unchanged then p_error
                -- Keep the earlier error for a state the worker did not see
                else meeting_error
            end,
            meeting_in_sync = case
                -- Keep a meeting marked keep during the claim
                when v_meeting_in_sync is null then null
                -- Mark the session in sync only when its state is unchanged
                else v_state_unchanged
            end,
            meeting_provider_host_user = null,
            meeting_sync_claimed_at = null
        where session_id = p_session_id;

    -- Report that no claim target was given
    else
        return false;
    end if;

    -- Report that the claim was held and released
    return true;
end;
$$ language plpgsql;
