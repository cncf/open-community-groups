-- update_notification marks a notification as processed and stores any error.
create or replace function update_notification(
    p_notification_id uuid,
    p_error text,
    p_delivery_claimed_at timestamptz
)
returns void as $$
begin
    -- Reject blank failure reasons, which operators could not act on
    if p_error is not null and btrim(p_error) = '' then
        raise exception 'delivery error is required';
    end if;

    -- Finalize the claimed notification with the delivery outcome
    update notification
    set
        delivery_status = case when p_error is null then 'processed' else 'failed' end,
        error = p_error,
        next_delivery_attempt_at = null,
        processed_at = current_timestamp
    where notification_id = p_notification_id
    and delivery_status = 'processing'
    and delivery_claimed_at = p_delivery_claimed_at;

    -- Reject stale or missing delivery claims
    if not found then
        raise exception 'notification delivery claim not found or no longer active';
    end if;
end;
$$ language plpgsql;
