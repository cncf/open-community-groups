-- mark_stale_processing_notifications_unknown marks stale claims for review.
create or replace function mark_stale_processing_notifications_unknown(
    p_processing_timeout_seconds bigint
)
returns integer as $$
declare
    v_template_data_ids uuid[];
    v_updated_count integer;
begin
    -- Validate the processing timeout before checking stale claims
    if p_processing_timeout_seconds <= 0 then
        raise exception 'processing timeout must be positive';
    end if;

    -- Mark abandoned claims whose delivery outcome can no longer be known
    with stale_notifications as (
        select notification_id, kind, notification_template_data_id
        from notification
        where delivery_status = 'processing'
        and delivery_claimed_at < current_timestamp - make_interval(
            secs => p_processing_timeout_seconds::double precision
        )
        for update
    ),
    updated_notifications as (
        update notification n
        set
            delivery_status = 'delivery-unknown',
            error = 'delivery outcome unknown after processing timeout',
            next_delivery_attempt_at = null,
            notification_template_data_id = case
                -- Detach sensitive password-reset payloads once delivery becomes terminal
                when sn.kind = 'password-reset' then null
                -- Keep template data links for ordinary notifications
                else n.notification_template_data_id
            end,
            processed_at = current_timestamp
        from stale_notifications sn
        where n.notification_id = sn.notification_id
        returning sn.kind, sn.notification_template_data_id
    )
    select
        count(*)::integer,
        array_agg(distinct notification_template_data_id) filter (
            where kind = 'password-reset' and notification_template_data_id is not null
        )
    into v_updated_count, v_template_data_ids
    from updated_notifications;

    -- Delete unreferenced password-reset template data so raw tokens do not persist at rest
    perform delete_unreferenced_notification_template_data(v_template_data_ids);

    -- Return the number of stale notifications marked unknown
    return coalesce(v_updated_count, 0);
end;
$$ language plpgsql;
