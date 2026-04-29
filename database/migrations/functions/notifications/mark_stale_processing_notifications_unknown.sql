-- mark_stale_processing_notifications_unknown marks stale claims for review.
create or replace function mark_stale_processing_notifications_unknown(
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

    -- Mark abandoned claims whose delivery outcome can no longer be known
    with updated_notifications as (
        update notification
        set
            delivery_status = 'delivery-unknown',
            error = 'delivery outcome unknown after processing timeout',
            processed_at = current_timestamp
        where delivery_status = 'processing'
        and delivery_claimed_at < current_timestamp - make_interval(
            secs => p_processing_timeout_seconds::double precision
        )
        returning 1
    )
    select count(*)::integer
    into v_updated_count
    from updated_notifications;

    return v_updated_count;
end;
$$ language plpgsql;
