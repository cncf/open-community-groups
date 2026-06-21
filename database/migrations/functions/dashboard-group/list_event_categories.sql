-- list_event_categories returns all event categories for a alliance.
create or replace function list_event_categories(p_alliance_id uuid)
returns json as $$
    select coalesce(json_agg(json_build_object(
        'events_count', coalesce(stats.events_count, 0),
        'event_category_id', ec.event_category_id,
        'name', ec.name,
        'slug', ec.slug
    ) order by ec."order" nulls last, ec.name), '[]')
    from event_category ec
    left join (
        select
            e.event_category_id,
            count(*) as events_count
        from event_category ec_filter
        join event e on e.event_category_id = ec_filter.event_category_id
        where ec_filter.alliance_id = p_alliance_id
        group by e.event_category_id
    ) stats using (event_category_id)
    where ec.alliance_id = p_alliance_id;
$$ language sql;
