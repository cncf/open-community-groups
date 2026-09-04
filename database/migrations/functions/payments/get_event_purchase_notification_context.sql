-- Returns identifiers used to compose purchase completion notifications.
create or replace function get_event_purchase_notification_context(
    p_group_id uuid,
    p_event_purchase_id uuid
)
returns jsonb as $$
    select jsonb_build_object(
        'community_id', g.community_id,
        'event_id', e.event_id
    )
    from event_purchase ep
    join event e on e.event_id = ep.event_id
    join "group" g on g.group_id = e.group_id
    where ep.event_purchase_id = p_event_purchase_id
    and e.group_id = p_group_id;
$$ language sql;
