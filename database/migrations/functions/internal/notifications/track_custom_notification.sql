-- track_custom_notification stores a sent custom notification and audit log.
-- The scope is the event when present, otherwise the group, otherwise the
-- community, whose audit details also describe the recipient filters.
create or replace function track_custom_notification(
    p_created_by uuid,
    p_community_id uuid,
    p_event_id uuid,
    p_group_id uuid,
    p_recipient_count int,
    p_subject text,
    p_body text,
    p_recipient_filters jsonb
)
returns void as $$
    with insert_custom_notification as (
        -- Store the sent custom notification in its narrowest scope
        insert into custom_notification (
            body,
            community_id,
            created_by,
            event_id,
            group_id,
            subject
        )
        values (
            p_body,
            case when p_event_id is null and p_group_id is null then p_community_id else null end,
            p_created_by,
            p_event_id,
            case when p_event_id is null then p_group_id else null end,
            p_subject
        )
        returning 1
    )
    -- Track the custom notification against its scope
    select insert_audit_log(
        p_action => case
            when p_event_id is not null then 'event_custom_notification_sent'
            when p_group_id is not null then 'group_custom_notification_sent'
            else 'community_custom_notification_sent'
        end,
        p_actor_user_id => p_created_by,
        p_resource_type => case
            when p_event_id is not null then 'event'
            when p_group_id is not null then 'group'
            else 'community'
        end,
        p_resource_id => coalesce(p_event_id, p_group_id, p_community_id),
        p_community_id => p_community_id,
        p_group_id => p_group_id,
        p_event_id => p_event_id,
        p_details => jsonb_build_object(
            'recipient_count',
            p_recipient_count,
            'subject',
            p_subject
        ) || case
            when p_event_id is null and p_group_id is null then
                describe_community_contact_filters(p_community_id, p_recipient_filters)
            else '{}'::jsonb
        end
    )
    from insert_custom_notification;
$$ language sql;
