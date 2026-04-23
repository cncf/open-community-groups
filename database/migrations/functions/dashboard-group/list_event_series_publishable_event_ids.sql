-- list_event_series_publishable_event_ids returns publishable events for a series action.
create or replace function list_event_series_publishable_event_ids(
    p_group_id uuid,
    p_event_id uuid
)
returns uuid[] as $$
    with selected_event as (
        select
            event_id,
            event_series_id,
            name,
            starts_at
        from event
        where event_id = p_event_id
        and group_id = p_group_id
        and deleted = false
        and canceled = false
    ),
    publishable_events as (
        select
            e.event_id,
            e.name,
            e.starts_at
        from selected_event se
        join event e on e.event_series_id = se.event_series_id
        where se.event_series_id is not null
        and e.group_id = p_group_id
        and e.deleted = false
        and e.canceled = false

        union all

        select
            se.event_id,
            se.name,
            se.starts_at
        from selected_event se
        where se.event_series_id is null
    )
    select coalesce(
        array_agg(event_id order by starts_at nulls last, name asc, event_id asc),
        '{}'::uuid[]
    )
    from publishable_events;
$$ language sql;
