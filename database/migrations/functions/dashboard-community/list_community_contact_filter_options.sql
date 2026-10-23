-- Returns the group, group category and region contact filter options of a
-- community. Group options list the active groups by label; category and
-- region options carry the number of active groups in each option;
-- has_subgroups tells whether any active group has an active parent group.
create or replace function list_community_contact_filter_options(p_community_id uuid)
returns json as $$
    with
        -- Select the community groups that can be contacted
        available_groups as (
            select
                cg.group_category_id,
                cg.group_id,
                cg.parent_group_id,
                cg.region_id
            from community_contact_groups(p_community_id) cg
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
        -- Label available groups for individual selection
        groups as (
            select coalesce(
                json_agg(
                    json_build_object(
                        'group_id', l.group_id,
                        'label', l.label
                    )
                    order by l.label, l.group_id
                ),
                '[]'
            ) as options
            from available_groups ag
            join community_contact_group_labels(p_community_id) l on l.group_id = ag.group_id
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
        'groups', gs.options,
        'has_subgroups', exists (
            select 1
            from available_groups child
            join available_groups parent on parent.group_id = child.parent_group_id
        ),
        'no_region_groups_count', (
            select count(*)::int
            from available_groups ag
            where ag.region_id is null
        ),
        'regions', rs.options
    )
    from group_categories gcs, groups gs, regions rs;
$$ language sql;
