-- Returns the publicly visible events that match the search filters provided,
-- with the fields callers need to sort, paginate and locate them. The bbox and
-- distance filters use the event location, falling back to the group location,
-- while the returned location is the event's own location. Distances are only
-- computed when sorting by distance from the viewer location. A non-empty group
-- selection that resolves to no group matches nothing. Uses PL/pgSQL with
-- `force_custom_plan` so each call is planned with the actual filter values.
create or replace function search_events_matches(p_filters jsonb)
returns table (
    community_id uuid,
    distance double precision,
    event_id uuid,
    group_id uuid,
    location geography,
    starts_at timestamptz
) as $$
declare
    v_bbox geometry;
    v_community_ids uuid[];
    v_event_category text[];
    v_filters record;
    v_group_category text[];
    v_group_ids uuid[];
    v_kind text[];
    v_max_distance real;
    v_region text[];
    v_sort_by text := coalesce(p_filters->>'sort_by', 'date');
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

    -- Normalize selected event categories
    if p_filters ? 'event_category' then
        select array_agg(lower(e::text)) into v_event_category
        from jsonb_array_elements_text(p_filters->'event_category') e;
    end if;

    -- Resolve selected groups within the selected community scope
    if p_filters ? 'group' and jsonb_array_length(p_filters->'group') > 0 then
        select coalesce(array_agg(g.group_id), array[]::uuid[]) into v_group_ids
        from jsonb_array_elements_text(p_filters->'group') e
        join "group" g on (g.slug = e or g.slug_pretty = e)
        where v_community_ids is null
        or g.community_id = any(v_community_ids);
    end if;

    -- Normalize selected group categories
    if p_filters ? 'group_category' then
        select array_agg(lower(e::text)) into v_group_category
        from jsonb_array_elements_text(p_filters->'group_category') e;
    end if;

    -- Normalize selected event kinds
    if p_filters ? 'kind' then
        select array_agg(e::text) into v_kind
        from jsonb_array_elements_text(p_filters->'kind') e;
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

    -- Return the publicly visible events matching every filter
    return query
    select
        g.community_id,
        case
            when v_sort_by = 'distance'
            and v_user_location is not null then
                st_distance(coalesce(e.location, g.location), v_user_location)
            else null
        end as distance,
        e.event_id,
        e.group_id,
        e.location,
        e.starts_at
    from event e
    join "group" g on g.group_id = e.group_id
    join community c on c.community_id = g.community_id
    join group_category gc on gc.group_category_id = g.group_category_id
    join event_category ec on ec.event_category_id = e.event_category_id
    left join region r on r.region_id = g.region_id
    where c.active = true
    and is_event_public(e, g)
    and e.canceled = false
    and e.test_event = false
    and
        case when v_bbox is not null then
        st_intersects(coalesce(e.location, g.location), v_bbox) else true end
    and
        case when v_community_ids is not null then
        g.community_id = any(v_community_ids) else true end
    and
        case when cardinality(v_event_category) > 0 then
        ec.slug = any(v_event_category) else true end
    and
        case when cardinality(v_group_category) > 0 then
        gc.normalized_name = any(v_group_category) else true end
    and
        case when v_group_ids is not null then
        g.group_id = any(v_group_ids) else true end
    and
        case when cardinality(v_kind) > 0 then
        e.event_kind_id = any(v_kind) else true end
    and
        case when cardinality(v_region) > 0 then
        r.normalized_name = any(v_region) else true end
    and
        case when v_filters.date_from is not null then
        e.starts_at >= v_filters.date_from else true end
    and
        case when v_filters.date_to is not null then
        e.starts_at < (v_filters.date_to + interval '1 day') else true end
    and
        case when v_max_distance is not null and v_user_location is not null then
        st_dwithin(v_user_location, coalesce(e.location, g.location), v_max_distance) else true end
    and
        case when v_tsquery_with_prefix_matching is not null then
            v_tsquery_with_prefix_matching @@ e.tsdoc
        else true end;
end
$$ language plpgsql set plan_cache_mode = force_custom_plan;
