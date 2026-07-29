-- Returns public full information about an event.
create or replace function get_public_event_full(
    p_community_id uuid,
    p_group_id uuid,
    p_event_id uuid
)
returns json as $$
    select (
        (get_event_full(p_community_id, p_group_id, p_event_id)::jsonb - 'ticket_types')
        || jsonb_strip_nulls(
            jsonb_build_object(
                'ticket_types', list_public_event_ticket_types(p_event_id)
            )
        )
    )::json;
$$ language sql;
