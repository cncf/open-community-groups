-- list_group_categories returns all group categories for a community.
create or replace function list_group_categories(
    p_community_id uuid
)
returns json as $$
    select coalesce(json_agg(
        json_build_object(
            'group_category_id', gc.group_category_id,
            'name', gc.name,
            'slug', gc.normalized_name,
            'order', gc."order"
        ) order by gc."order" nulls last, gc.name
    ), '[]')
    from group_category gc
    where gc.community_id = p_community_id;
$$ language sql;
