-- list_event_series_event_ids returns active events linked to the selected event series.
create or replace function list_event_series_event_ids(
    p_group_id uuid,
    p_event_id uuid
)
returns uuid[] as $$
    with selected_event as (
        select event_series_id
        from event
        where event_id = p_event_id
        and group_id = p_group_id
        and deleted = false
    )
    select coalesce(
        array_agg(e.event_id order by e.starts_at nulls last, e.name asc, e.event_id asc),
        '{}'::uuid[]
    )
    from selected_event se
    join event e on e.event_series_id = se.event_series_id
    where se.event_series_id is not null
    and e.group_id = p_group_id
    and e.deleted = false;
$$ language sql;
