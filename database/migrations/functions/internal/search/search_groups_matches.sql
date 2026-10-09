-- Returns the groups that match the search filters provided, with the fields
-- callers need to sort, paginate and locate them. Only publicly visible groups
-- match unless inactive groups are requested, and deleted groups never match.
-- Distances are only computed when sorting by distance from the viewer
-- location. Uses PL/pgSQL with `force_custom_plan` so each call is planned
-- with the actual filter values.
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
    v_community_ids uuid[];
    v_filters record;
    v_group_category text[];
    v_include_inactive boolean := coalesce((p_filters->>'include_inactive')::boolean, false);
    v_max_distance real;
    v_region text[];
    v_sort_by text := coalesce(p_filters->>'sort_by', 'name');
    v_tsquery_with_prefix_matching tsquery;
    v_user_location geography;
begin
    -- Prepare shared filters and geographic bounds
    select *
    into v_filters
    from parse_search_filters(p_filters);
    v_bbox := search_bbox_envelope(p_filters);

    -- Resolve selected communities by public names
    if p_filters ? 'community' and jsonb_array_length(p_filters->'community') > 0 then
        select coalesce(array_agg(c.community_id), array[]::uuid[]) into v_community_ids
        from jsonb_array_elements_text(p_filters->'community') e
        join community c on c.name = e;
    end if;

    -- Normalize selected group categories
    if p_filters ? 'group_category' then
        select array_agg(lower(e::text)) into v_group_category
        from jsonb_array_elements_text(p_filters->'group_category') e;
    end if;

    -- Prepare proximity filtering
    if p_filters ? 'latitude' and p_filters ? 'longitude' then
        v_user_location := jsonb_geography_point(p_filters);

        -- Apply an optional maximum distance around the user location
        if p_filters ? 'distance' then
            v_max_distance := (p_filters->>'distance')::real;
        end if;
    end if;

    -- Normalize selected regions
    if p_filters ? 'region' then
        select array_agg(lower(e::text)) into v_region
        from jsonb_array_elements_text(p_filters->'region') e;
    end if;

    -- Build a prefix-matching text search query
    if v_filters.ts_query is not null then
        v_tsquery_with_prefix_matching := prefix_tsquery(
            get_current_ts_config(),
            v_filters.ts_query
        );
    end if;

    -- Return the visible groups matching every filter
    return query
    select
        g.community_id,
        g.created_at,
        case
            when v_sort_by = 'distance'
            and v_user_location is not null then
                st_distance(g.location, v_user_location)
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
    and
        case when v_include_inactive then
        g.deleted = false else is_group_public(g) end
    and
        case when v_bbox is not null then
        st_intersects(g.location, v_bbox) else true end
    and
        case when v_community_ids is not null then
        g.community_id = any(v_community_ids) else true end
    and
        case when cardinality(v_group_category) > 0 then
        gc.normalized_name = any(v_group_category) else true end
    and
        case when v_max_distance is not null and v_user_location is not null then
        st_dwithin(v_user_location, g.location, v_max_distance) else true end
    and
        case when cardinality(v_region) > 0 then
        r.normalized_name = any(v_region) else true end
    and
        case when v_tsquery_with_prefix_matching is not null then
            v_tsquery_with_prefix_matching @@ g.tsdoc
        else true end;
end
$$ language plpgsql set plan_cache_mode = force_custom_plan;
