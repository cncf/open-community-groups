-- Returns summary information about an event using only the event ID.
create or replace function get_event_summary_by_id(p_alliance_id uuid, p_event_id uuid)
returns json as $$
    select get_event_summary(p_alliance_id, g.group_id, e.event_id)
    from event e
    join "group" g using (group_id)
    where e.event_id = p_event_id
    and g.alliance_id = p_alliance_id;
$$ language sql;
