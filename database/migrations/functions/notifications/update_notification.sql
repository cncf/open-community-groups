-- update_notification marks a notification as processed and stores any error.
create or replace function update_notification(
    p_notification_id uuid,
    p_error text
)
returns void as $$
begin
    -- Finalize the claimed notification with the delivery outcome
    update notification
    set
        delivery_status = case when p_error is null then 'processed' else 'failed' end,
        error = p_error,
        processed_at = current_timestamp
    where notification_id = p_notification_id
    and delivery_status = 'processing';

    if not found then
        raise exception 'claimed notification not found or already finalized';
    end if;
end;
$$ language plpgsql;
