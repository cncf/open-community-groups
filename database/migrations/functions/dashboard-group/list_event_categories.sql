-- list_event_categories returns all event categories for a community.
create or replace function list_event_categories(p_community_id uuid)
returns json as $$
    select coalesce(json_agg(json_build_object(
        'event_category_id', ec.event_category_id,
        'name', ec.name,
        'slug', ec.slug
    ) order by ec."order" nulls last, ec.name), '[]')
    from event_category ec
    where ec.community_id = p_community_id;
$$ language sql;