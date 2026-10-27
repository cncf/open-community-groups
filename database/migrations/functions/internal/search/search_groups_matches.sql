-- Returns the groups that match the search filters provided, with the fields
-- callers need to sort, paginate and locate them. Only publicly visible groups
-- of active communities match. Distances are only computed when sorting by
-- distance from the viewer location. Uses PL/pgSQL with `force_custom_plan`
-- so each call is planned with the actual filter values.
create or replace function search_groups_matches(p_filters jsonb)
returns table (
    community_id uuid,
    created_at timestamptz,
    distance double precision,
    group_id uuid,
    location geography,
    name text
) as $$
declare
    v_bbox geometry;
    v_explore record;
    v_filters record;
    v_sort_by text := coalesce(p_filters->>'sort_by', 'name');
begin
    -- Prepare shared filters and geographic bounds
    select *
    into v_filters
    from parse_search_filters(p_filters);
    select *
    into v_explore
    from parse_explore_filters(p_filters);
    v_bbox := search_bbox_envelope(p_filters);

    -- Return the visible groups matching every filter
    return query
    select
        g.community_id,
        g.created_at,
        case
            when v_sort_by = 'distance'
            and v_explore.user_location is not null then
                st_distance(g.location, v_explore.user_location)
            else null
        end as distance,
        g.group_id,
        g.location,
        g.name
    from "group" g
    join community c on c.community_id = g.community_id
    join group_category gc on gc.group_category_id = g.group_category_id
    left join region r on r.region_id = g.region_id
    where c.active = true
    and is_group_public(g)
    and
        case when v_bbox is not null then
        st_intersects(g.location, v_bbox) else true end
    and
        case when v_explore.community_ids is not null then
        g.community_id = any(v_explore.community_ids) else true end
    and
        case when cardinality(v_explore.group_category) > 0 then
        gc.normalized_name = any(v_explore.group_category) else true end
    and
        case when v_explore.max_distance is not null and v_explore.user_location is not null then
        st_dwithin(v_explore.user_location, g.location, v_explore.max_distance) else true end
    and
        case when cardinality(v_explore.region) > 0 then
        r.normalized_name = any(v_explore.region) else true end
    and
        case when v_filters.tsquery is not null then
        v_filters.tsquery @@ g.tsdoc else true end;
end
$$ language plpgsql stable set plan_cache_mode = force_custom_plan;
