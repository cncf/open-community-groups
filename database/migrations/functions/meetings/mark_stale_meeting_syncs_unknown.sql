-- mark_stale_meeting_syncs_unknown marks stale sync claims for review.
create or replace function mark_stale_meeting_syncs_unknown(
    p_processing_timeout_seconds bigint
)
returns integer as $$
declare
    v_updated_count integer;
begin
    -- Validate the processing timeout before checking stale claims
    if p_processing_timeout_seconds <= 0 then
        raise exception 'processing timeout must be positive';
    end if;

    -- Mark abandoned event meeting claims whose outcome can no longer be known,
    -- preserving keep decisions, create-attempt and sticky host tracking
    with updated_events as (
        update event
        set
            meeting_error = case
                -- Preserve prior error state when the event was marked keep during the claim
                when meeting_in_sync is null then meeting_error
                -- Record the unknown processing timeout outcome
                else 'meeting synchronization outcome unknown after processing timeout'
            end,
            meeting_in_sync = case
                -- Preserve a keep decision recorded during the stale claim
                when meeting_in_sync is null then null
                -- Mark the event in sync so operators can review the unknown outcome
                else true
            end,
            meeting_last_provider_host_user = coalesce(
                meeting_provider_host_user,
                meeting_last_provider_host_user
            ),
            meeting_next_sync_at = null,
            meeting_provider_host_user = null,
            meeting_sync_attempts = 0,
            meeting_sync_claimed_at = null
        where meeting_sync_claimed_at < current_timestamp - make_interval(
            secs => p_processing_timeout_seconds::double precision
        )
        returning 1
    ),
    -- Mark abandoned session meeting claims whose outcome can no longer be known,
    -- preserving keep decisions, create-attempt and sticky host tracking
    updated_sessions as (
        update session
        set
            meeting_error = case
                -- Preserve prior error state when the session was marked keep during the claim
                when meeting_in_sync is null then meeting_error
                -- Record the unknown processing timeout outcome
                else 'meeting synchronization outcome unknown after processing timeout'
            end,
            meeting_in_sync = case
                -- Preserve a keep decision recorded during the stale claim
                when meeting_in_sync is null then null
                -- Mark the session in sync so operators can review the unknown outcome
                else true
            end,
            meeting_last_provider_host_user = coalesce(
                meeting_provider_host_user,
                meeting_last_provider_host_user
            ),
            meeting_next_sync_at = null,
            meeting_provider_host_user = null,
            meeting_sync_attempts = 0,
            meeting_sync_claimed_at = null
        where meeting_sync_claimed_at < current_timestamp - make_interval(
            secs => p_processing_timeout_seconds::double precision
        )
        returning 1
    ),
    -- Release stale orphan delete claims so they can be retried
    updated_meetings as (
        update meeting
        set
            next_sync_at = null,
            sync_claimed_at = null,
            updated_at = current_timestamp
        where event_id is null
          and session_id is null
          and sync_claimed_at < current_timestamp - make_interval(
              secs => p_processing_timeout_seconds::double precision
          )
        returning 1
    )
    select count(*)::integer
    into v_updated_count
    from (
        select 1 from updated_events
        union all
        select 1 from updated_sessions
        union all
        select 1 from updated_meetings
    ) updated_claims;

    -- Return the total number of recovered stale claims
    return v_updated_count;
end;
$$ language plpgsql;
