-- Enqueues and tracks a custom notification atomically. Event and group
-- notifications are scoped to p_group_id, so recipients who muted that group
-- are skipped; community notifications have no group scope.
create or replace function enqueue_tracked_custom_notification(
    p_kind text,
    p_template_data jsonb,
    p_attachments jsonb,
    p_recipients uuid[],
    p_created_by uuid,
    p_community_id uuid,
    p_event_id uuid,
    p_group_id uuid,
    p_recipient_count int,
    p_subject text,
    p_body text,
    p_recipient_filters jsonb default null
)
returns void as $$
begin
    -- Create notification rows first so enqueue failures prevent tracking
    perform enqueue_notification(
        p_kind,
        p_template_data,
        p_attachments,
        p_recipients,
        case when p_group_id is null then null else array[p_group_id] end
    );

    -- Track the custom notification after enqueue succeeds
    perform track_custom_notification(
        p_created_by,
        p_community_id,
        p_event_id,
        p_group_id,
        p_recipient_count,
        p_subject,
        p_body,
        p_recipient_filters
    );
end;
$$ language plpgsql;
