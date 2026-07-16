-- Marks a claimed notification with an unknown delivery outcome.
create or replace function mark_notification_delivery_unknown(
    p_notification_id uuid,
    p_error text,
    p_delivery_claimed_at timestamptz
)
returns void as $$
begin
    -- Validate delivery metadata before changing notification state
    if p_error is null or btrim(p_error) = '' then
        raise exception 'delivery error is required';
    end if;

    -- Finalize the claim without risking an automatic duplicate delivery
    update notification
    set
        delivery_status = 'delivery-unknown',
        error = p_error,
        next_delivery_attempt_at = null,
        processed_at = current_timestamp
    where notification_id = p_notification_id
    and delivery_status = 'processing'
    and delivery_claimed_at = p_delivery_claimed_at;

    -- Confirm that the claimed notification changed state
    if not found then
        raise exception 'notification delivery claim not found or no longer active';
    end if;
end;
$$ language plpgsql;
