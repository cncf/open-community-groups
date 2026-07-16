-- Manually requeues selected terminal notifications after operator review.
create or replace function manual_requeue_notifications(
    p_notification_ids uuid[],
    p_reason text
)
returns integer as $$
declare
    v_notification record;
    v_updated_count integer := 0;
begin
    -- Validate the operator request before requeueing terminal rows
    if p_notification_ids is null or cardinality(p_notification_ids) = 0 then
        raise exception 'notification ids are required';
    end if;
    if p_reason is null or btrim(p_reason) = '' then
        raise exception 'requeue reason is required';
    end if;

    -- Lock selected terminal notifications in a stable order
    for v_notification in
        select
            notification_id,
            delivery_status,
            error
        from notification
        where notification_id = any(p_notification_ids)
        and delivery_status in ('delivery-unknown', 'failed')
        order by notification_id
        for update
    loop
        -- Return the terminal notification to the immediate delivery queue
        update notification
        set
            delivery_attempts = 0,
            delivery_claimed_at = null,
            delivery_status = 'pending',
            error = p_reason,
            next_delivery_attempt_at = null,
            processed_at = null
        where notification_id = v_notification.notification_id;

        -- Preserve the operator reason and previous outcome in append-only history
        perform insert_audit_log(
            p_action => 'notification_manually_requeued',
            p_actor_user_id => null,
            p_resource_type => 'notification',
            p_resource_id => v_notification.notification_id,
            p_details => jsonb_build_object(
                'database_user', current_user,
                'previous_delivery_status', v_notification.delivery_status,
                'previous_error', v_notification.error,
                'reason', p_reason
            )
        );

        v_updated_count := v_updated_count + 1;
    end loop;

    return v_updated_count;
end;
$$ language plpgsql;
