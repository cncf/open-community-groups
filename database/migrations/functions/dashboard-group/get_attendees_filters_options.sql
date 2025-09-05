-- Returns the filters options for the group attendees page.
create or replace function get_attendees_filters_options(p_group_id uuid)
returns json as $$
    with events as (
        select e.event_id
        from event e
        where e.group_id = p_group_id
        and e.deleted = false
        order by e.starts_at desc nulls last, e.name asc
    )
    select json_build_object(
        'events', (select coalesce(json_agg(get_event_summary(event_id)), '[]'::json) from events)
    );
$$ language sql;
