-- Clears stored template data and cancels pending password-reset emails for inactive tokens.
create or replace function purge_password_reset_notification_data(
    p_user_ids uuid[]
)
returns void as $$
declare
    v_template_data_ids uuid[];
begin
    -- Return immediately when no users are supplied
    if p_user_ids is null or cardinality(p_user_ids) = 0 then
        return;
    end if;

    -- Detach template data and cancel non-processing password-reset notifications
    with target_notifications as (
        select notification_id, notification_template_data_id
        from notification
        where user_id = any(p_user_ids)
        and kind = 'password-reset'
        and delivery_status <> 'processing'
        and (
            notification_template_data_id is not null
            or delivery_status = 'pending'
        )
        for update skip locked
    ),
    updated as (
        update notification n
        set
            delivery_status = case
                -- Cancel pending notifications whose token is no longer active
                when n.delivery_status = 'pending' then 'failed'
                -- Keep finalized statuses unchanged
                else n.delivery_status
            end,
            error = case
                -- Record why pending notifications were canceled
                when n.delivery_status = 'pending' then 'password reset token no longer active'
                -- Preserve any existing delivery error
                else n.error
            end,
            next_delivery_attempt_at = case
                -- Clear retry schedules for canceled pending notifications
                when n.delivery_status = 'pending' then null
                -- Keep existing schedule on other rows
                else n.next_delivery_attempt_at
            end,
            notification_template_data_id = null,
            processed_at = case
                -- Stamp completion time on canceled pending notifications
                when n.delivery_status = 'pending' then current_timestamp
                -- Keep existing completion time on already finalized rows
                else n.processed_at
            end
        from target_notifications tn
        where n.notification_id = tn.notification_id
        returning tn.notification_template_data_id
    )
    select array_agg(distinct notification_template_data_id)
    into v_template_data_ids
    from updated
    where notification_template_data_id is not null;

    -- Remove now-unreferenced password-reset template data rows
    perform delete_unreferenced_notification_template_data(v_template_data_ids);
end;
$$ language plpgsql;
