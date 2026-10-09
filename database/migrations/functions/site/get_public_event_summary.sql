-- Returns the summary of an event when its public page is available, or null.
create or replace function get_public_event_summary(p_event_id uuid)
returns json as $$
    select get_event_summary(g.community_id, g.group_id, e.event_id)
    from event e
    join "group" g on g.group_id = e.group_id
    join community c on c.community_id = g.community_id
    where e.event_id = p_event_id
    and c.active = true
    and is_event_public(e, g);
$$ language sql;
