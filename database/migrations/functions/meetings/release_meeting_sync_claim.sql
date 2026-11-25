-- release_meeting_sync_claim releases a retryable meeting sync claim,
-- optionally scheduling the next sync attempt after a backoff delay. Rows
-- marked keep (null) or materially edited while claimed reset retry state so
-- follow-up work starts with a fresh attempt budget.
create or replace function release_meeting_sync_claim(
    p_event_id uuid,
    p_meeting_id uuid,
    p_session_id uuid,
    p_sync_claimed_at timestamptz,
    p_retry_after_seconds bigint default null,
    p_sync_state_hash text default null
) returns void as $$
declare
    v_meeting_in_sync boolean;
    v_next_sync_at timestamptz;
    v_reset_retry_budget boolean;
begin
    -- Reject non-positive retry delays when backoff is requested
    if p_retry_after_seconds is not null and p_retry_after_seconds <= 0 then
        raise exception 'retry delay must be positive';
    end if;

    -- Compute the next eligible sync timestamp using the database clock
    if p_retry_after_seconds is not null then
        v_next_sync_at := current_timestamp + make_interval(
            secs => p_retry_after_seconds::double precision
        );
    end if;

    -- Event meeting case
    if p_event_id is not null then
        -- Lock the event while the worker still holds its claim
        select e.meeting_in_sync
        into v_meeting_in_sync
        from event e
        where e.event_id = p_event_id
          and e.meeting_in_sync is distinct from true
          and e.meeting_sync_claimed_at = p_sync_claimed_at
        for update of e;

        -- Ignore claims that are no longer held
        if not found then
            return;
        end if;

        -- Reset retry budget when the row was marked keep or edited during the claim
        v_reset_retry_budget := v_meeting_in_sync is null
            or (
                p_sync_state_hash is not null
                and get_event_meeting_sync_state_hash(p_event_id)
                    is distinct from p_sync_state_hash
            );

        -- Release the event claim and preserve sticky host tracking
        update event
        set
            meeting_last_provider_host_user = coalesce(
                meeting_provider_host_user,
                meeting_last_provider_host_user
            ),
            meeting_next_sync_at = case
                -- Clear backoff for kept or materially edited rows
                when v_reset_retry_budget then null
                -- Apply the requested backoff delay
                else v_next_sync_at
            end,
            meeting_provider_host_user = null,
            meeting_sync_attempts = case
                -- Reset retry attempts for kept or materially edited rows
                when v_reset_retry_budget then 0
                -- Preserve the accumulated retry attempts for the active sync cycle
                else meeting_sync_attempts
            end,
            meeting_sync_claimed_at = null
        where event_id = p_event_id;

    -- Session meeting case
    elsif p_session_id is not null then
        -- Lock the session while the worker still holds its claim
        select s.meeting_in_sync
        into v_meeting_in_sync
        from session s
        where s.session_id = p_session_id
          and s.meeting_in_sync is distinct from true
          and s.meeting_sync_claimed_at = p_sync_claimed_at
        for update of s;

        -- Ignore claims that are no longer held
        if not found then
            return;
        end if;

        -- Reset retry budget when the row was marked keep or edited during the claim
        v_reset_retry_budget := v_meeting_in_sync is null
            or (
                p_sync_state_hash is not null
                and get_session_meeting_sync_state_hash(p_session_id)
                    is distinct from p_sync_state_hash
            );

        -- Release the session claim and preserve sticky host tracking
        update session
        set
            meeting_last_provider_host_user = coalesce(
                meeting_provider_host_user,
                meeting_last_provider_host_user
            ),
            meeting_next_sync_at = case
                -- Clear backoff for kept or materially edited rows
                when v_reset_retry_budget then null
                -- Apply the requested backoff delay
                else v_next_sync_at
            end,
            meeting_provider_host_user = null,
            meeting_sync_attempts = case
                -- Reset retry attempts for kept or materially edited rows
                when v_reset_retry_budget then 0
                -- Preserve the accumulated retry attempts for the active sync cycle
                else meeting_sync_attempts
            end,
            meeting_sync_claimed_at = null
        where session_id = p_session_id;

    -- Orphan meeting case
    elsif p_meeting_id is not null then
        update meeting
        set
            next_sync_at = v_next_sync_at,
            sync_claimed_at = null,
            updated_at = current_timestamp
        where meeting_id = p_meeting_id
          and sync_claimed_at = p_sync_claimed_at;
    end if;
end;
$$ language plpgsql;
