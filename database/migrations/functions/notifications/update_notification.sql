-- update_notification marks a notification as processed and stores any error.
create or replace function update_notification(
    p_notification_id uuid,
    p_error text,
    p_delivery_claimed_at timestamptz
)
returns void as $$
declare
    v_kind text;
    v_notification_template_data_id uuid;
begin
    -- Reject blank failure reasons, which operators could not act on
    if p_error is not null and btrim(p_error) = '' then
        raise exception 'delivery error is required';
    end if;

    -- Lock the claimed notification and capture its kind and template data id
    select kind, notification_template_data_id
    into v_kind, v_notification_template_data_id
    from notification
    where notification_id = p_notification_id
    and delivery_status = 'processing'
    and delivery_claimed_at = p_delivery_claimed_at
    for update;

    -- Reject stale or missing delivery claims
    if not found then
        raise exception 'notification delivery claim not found or no longer active';
    end if;

    -- Finalize the claimed notification and detach sensitive password-reset payloads
    update notification
    set
        delivery_status = case
            -- Mark clean deliveries as processed
            when p_error is null then 'processed'
            -- Mark terminal errors as failed
            else 'failed'
        end,
        error = p_error,
        next_delivery_attempt_at = null,
        notification_template_data_id = case
            -- Detach sensitive password-reset payloads once delivery finishes
            when v_kind = 'password-reset' then null
            -- Keep template data links for ordinary notifications
            else notification_template_data_id
        end,
        processed_at = current_timestamp
    where notification_id = p_notification_id;

    -- Delete unreferenced password-reset template data so raw tokens do not persist at rest
    if v_kind = 'password-reset' and v_notification_template_data_id is not null then
        perform delete_unreferenced_notification_template_data(
            array[v_notification_template_data_id]
        );
    end if;
end;
$$ language plpgsql;
