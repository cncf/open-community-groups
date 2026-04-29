-- mark_stale_meeting_auto_end_checks_unknown marks stale auto-end claims.
create or replace function mark_stale_meeting_auto_end_checks_unknown(
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

    -- Mark abandoned auto-end claims whose outcome can no longer be known
    with updated_meetings as (
        update meeting
        set
            auto_end_check_at = current_timestamp,
            auto_end_check_claimed_at = null,
            auto_end_check_outcome = 'error',
            updated_at = current_timestamp
        where auto_end_check_at is null
          and auto_end_check_claimed_at < current_timestamp - make_interval(
              secs => p_processing_timeout_seconds::double precision
          )
        returning 1
    )
    select count(*)::integer
    into v_updated_count
    from updated_meetings;

    return v_updated_count;
end;
$$ language plpgsql;
