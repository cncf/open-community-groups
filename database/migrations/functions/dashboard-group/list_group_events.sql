-- Returns all events for a group for dashboard administration.
create or replace function list_group_events(p_group_id uuid)
returns json as $$
    select coalesce(json_agg(
        get_event_summary(e.event_id)
    ), '[]')
    from (
        select e.event_id
        from event e
        where e.group_id = p_group_id
        order by e.starts_at desc nulls last, e.name asc
    ) e;
$$ language sql;