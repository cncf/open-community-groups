-- Enqueues and tracks a custom notification atomically.
create or replace function enqueue_tracked_custom_notification(
    p_kind text,
    p_template_data jsonb,
    p_attachments jsonb,
    p_recipients uuid[],
    p_created_by uuid,
    p_event_id uuid,
    p_group_id uuid,
    p_recipient_count int,
    p_subject text,
    p_body text
)
returns void as $$
begin
    -- Create notification rows first so enqueue failures prevent tracking
    perform enqueue_notification(
        p_kind,
        p_template_data,
        p_attachments,
        p_recipients
    );

    -- Track the custom notification after enqueue succeeds
    perform track_custom_notification(
        p_created_by,
        p_event_id,
        p_group_id,
        p_recipient_count,
        p_subject,
        p_body
    );
end;
$$ language plpgsql;
