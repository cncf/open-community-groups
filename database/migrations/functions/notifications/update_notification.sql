-- update_notification marks a notification as processed and stores any error.
create or replace function update_notification(
    p_notification_id uuid,
    p_error text
)
returns void as $$
    -- Mark the notification as processed
    update notification
    set
        error = p_error,
        processed = true,
        processed_at = current_timestamp
    where notification_id = p_notification_id;
$$ language sql;
