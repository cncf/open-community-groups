-- Returns the group category and region contact filter options of a community
-- with the number of active groups in each option.
create or replace function list_community_contact_filter_options(p_community_id uuid)
returns json as $$
    with
        -- Select the community groups that can be contacted
        available_groups as (
            select
                g.group_category_id,
                g.region_id
            from "group" g
            where g.community_id = p_community_id
            and g.active = true
            and g.deleted = false
        ),
        -- Count available groups per group category, keeping empty categories
        group_categories as (
            select coalesce(
                json_agg(
                    json_build_object(
                        'group_category_id', gc.group_category_id,
                        'groups_count', (
                            select count(*)::int
                            from available_groups ag
                            where ag.group_category_id = gc.group_category_id
                        ),
                        'name', gc.name
                    )
                    order by gc."order" nulls last, gc.name
                ),
                '[]'
            ) as options
            from group_category gc
            where gc.community_id = p_community_id
        ),
        -- Count available groups per region, keeping empty regions
        regions as (
            select coalesce(
                json_agg(
                    json_build_object(
                        'groups_count', (
                            select count(*)::int
                            from available_groups ag
                            where ag.region_id = r.region_id
                        ),
                        'name', r.name,
                        'region_id', r.region_id
                    )
                    order by r."order" nulls last, r.name
                ),
                '[]'
            ) as options
            from region r
            where r.community_id = p_community_id
        )
    -- Build the filter options payload
    select json_build_object(
        'group_categories', gcs.options,
        'no_region_groups_count', (
            select count(*)::int
            from available_groups ag
            where ag.region_id is null
        ),
        'regions', rs.options
    )
    from group_categories gcs, regions rs;
$$ language sql;
