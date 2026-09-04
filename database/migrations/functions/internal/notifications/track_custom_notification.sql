-- track_custom_notification stores a sent custom notification and audit log.
create or replace function track_custom_notification(
    p_created_by uuid,
    p_event_id uuid,
    p_group_id uuid,
    p_recipient_count int,
    p_subject text,
    p_body text
)
returns void as $$
    with insert_custom_notification as (
        -- Store the sent custom notification
        insert into custom_notification (body, created_by, event_id, group_id, subject)
        values (
            p_body,
            p_created_by,
            p_event_id,
            case when p_event_id is null then p_group_id else null end,
            p_subject
        )
        returning 1
    )
    -- Track the custom notification
    select insert_audit_log(
        p_action => case
            when p_event_id is null then 'group_custom_notification_sent'
            else 'event_custom_notification_sent'
        end,
        p_actor_user_id => p_created_by,
        p_resource_type => case
            when p_event_id is null then 'group'
            else 'event'
        end,
        p_resource_id => coalesce(p_event_id, p_group_id),
        p_group_id => p_group_id,
        p_event_id => p_event_id,
        p_details => jsonb_build_object(
            'recipient_count',
            p_recipient_count,
            'subject',
            p_subject
        )
    )
    from insert_custom_notification;
$$ language sql;
