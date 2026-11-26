-- Marks a claimed notification with an unknown delivery outcome.
create or replace function mark_notification_delivery_unknown(
    p_notification_id uuid,
    p_error text,
    p_delivery_claimed_at timestamptz
)
returns void as $$
declare
    v_kind text;
    v_notification_template_data_id uuid;
begin
    -- Validate delivery metadata before changing notification state
    if p_error is null or btrim(p_error) = '' then
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

    -- Confirm that the claimed notification is still active
    if not found then
        raise exception 'notification delivery claim not found or no longer active';
    end if;

    -- Finalize the claim without risking an automatic duplicate delivery
    update notification
    set
        delivery_status = 'delivery-unknown',
        error = p_error,
        next_delivery_attempt_at = null,
        notification_template_data_id = case
            -- Detach sensitive password-reset payloads once delivery becomes terminal
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
