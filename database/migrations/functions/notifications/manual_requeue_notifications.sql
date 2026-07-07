-- Manually requeues selected terminal notifications after operator review.
create or replace function manual_requeue_notifications(
    p_notification_ids uuid[],
    p_reason text
)
returns integer as $$
declare
    v_updated_count integer;
begin
    -- Validate the operator request before requeueing terminal rows
    if p_notification_ids is null or cardinality(p_notification_ids) = 0 then
        raise exception 'notification ids are required';
    end if;
    if p_reason is null or btrim(p_reason) = '' then
        raise exception 'requeue reason is required';
    end if;

    -- Return selected terminal notifications to the immediate delivery queue
    with updated_notifications as (
        update notification
        set
            delivery_attempts = 0,
            delivery_claimed_at = null,
            delivery_status = 'pending',
            error = p_reason,
            next_delivery_attempt_at = null,
            processed_at = null
        where notification_id = any(p_notification_ids)
        and delivery_status in ('delivery-unknown', 'failed')
        returning 1
    )
    select count(*)::integer
    into v_updated_count
    from updated_notifications;

    return v_updated_count;
end;
$$ language plpgsql;
