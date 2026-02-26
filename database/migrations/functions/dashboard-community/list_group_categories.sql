-- list_group_categories returns all group categories for a community.
create or replace function list_group_categories(
    p_community_id uuid
)
returns json as $$
    select coalesce(json_agg(
        json_build_object(
            'groups_count', coalesce(stats.groups_count, 0),
            'group_category_id', gc.group_category_id,
            'name', gc.name,
            'slug', gc.normalized_name,
            'order', gc."order"
        ) order by gc."order" nulls last, gc.name
    ), '[]')
    from group_category gc
    left join (
        select
            g.group_category_id,
            count(*) as groups_count
        from group_category gc_filter
        join "group" g on g.group_category_id = gc_filter.group_category_id
        where gc_filter.community_id = p_community_id
        group by g.group_category_id
    ) stats using (group_category_id)
    where gc.community_id = p_community_id;
$$ language sql;
