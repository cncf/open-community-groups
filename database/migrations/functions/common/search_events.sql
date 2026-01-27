-- Returns the events that match the filters provided.
create or replace function search_events(p_filters jsonb)
returns json as $$
declare
    v_bbox geometry;
    v_community_ids uuid[];
    v_date_from date := (p_filters->>'date_from');
    v_date_to date := (p_filters->>'date_to');
    v_event_category text[];
    v_group_category text[];
    v_group_ids uuid[];
    v_kind text[];
    v_limit int := (p_filters->>'limit')::int;
    v_max_distance real;
    v_offset int := (p_filters->>'offset')::int;
    v_region text[];
    v_sort_by text := coalesce(p_filters->>'sort_by', 'date');
    v_sort_direction text := case lower(coalesce(p_filters->>'sort_direction', 'asc'))
        when 'desc' then 'desc'
        else 'asc'
    end;
    v_tsquery_with_prefix_matching tsquery;
    v_user_location geography;
begin
    -- Prepare filters
    if p_filters ? 'bbox_ne_lat' and p_filters ? 'bbox_ne_lon' and p_filters ? 'bbox_sw_lat' and p_filters ? 'bbox_sw_lon' then
        v_bbox := st_makeenvelope(
            (p_filters->>'bbox_sw_lon')::real,
            (p_filters->>'bbox_sw_lat')::real,
            (p_filters->>'bbox_ne_lon')::real,
            (p_filters->>'bbox_ne_lat')::real,
            4326
        );
    end if;
    if p_filters ? 'community' and jsonb_array_length(p_filters->'community') > 0 then
        select coalesce(array_agg(c.community_id), array[]::uuid[]) into v_community_ids
        from jsonb_array_elements_text(p_filters->'community') e
        join community c on c.name = e;
    end if;
    if p_filters ? 'event_category' then
        select array_agg(lower(e::text)) into v_event_category
        from jsonb_array_elements_text(p_filters->'event_category') e;
    end if;
    if p_filters ? 'group' and jsonb_array_length(p_filters->'group') > 0 then
        select coalesce(array_agg(g.group_id), array[]::uuid[]) into v_group_ids
        from jsonb_array_elements_text(p_filters->'group') e
        join "group" g on g.slug = e;
    end if;
    if p_filters ? 'group_category' then
        select array_agg(lower(e::text)) into v_group_category
        from jsonb_array_elements_text(p_filters->'group_category') e;
    end if;
    if p_filters ? 'kind' then
        select array_agg(e::text) into v_kind
        from jsonb_array_elements_text(p_filters->'kind') e;
    end if;
    if p_filters ? 'latitude' and p_filters ? 'longitude' then
        v_user_location := st_setsrid(st_makepoint((p_filters->>'longitude')::real, (p_filters->>'latitude')::real), 4326);
        if p_filters ? 'distance' then
            v_max_distance := (p_filters->>'distance')::real;
        end if;
    end if;
    if p_filters ? 'region' then
        select array_agg(lower(e::text)) into v_region
        from jsonb_array_elements_text(p_filters->'region') e;
    end if;
    if p_filters ? 'ts_query' then
        select ts_rewrite(
            websearch_to_tsquery(p_filters->>'ts_query'),
            format('
                select
                    to_tsquery(lexeme),
                    to_tsquery(lexeme || '':*'')
                from unnest(tsvector_to_array(to_tsvector(%L))) as lexeme
                ', p_filters->>'ts_query'
            )
        ) into v_tsquery_with_prefix_matching;
    end if;

    return (
    with filtered_events as (
        select
            g.community_id,
            e.event_id,
            e.group_id,
            e.starts_at,
            coalesce(e.location, g.location) as location,
            case
                when v_sort_by = 'distance'
                and v_user_location is not null then
                    st_distance(coalesce(e.location, g.location), v_user_location)
                else null
            end as distance
        from event e
        join "group" g using (group_id)
        join group_category gc using (group_category_id)
        join event_category ec using (event_category_id)
        left join region r using (region_id)
        where g.active = true
        and e.published = true
        and e.canceled = false
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
            case when cardinality(v_group_ids) > 0 then
            g.group_id = any(v_group_ids) else true end
        and
            case when cardinality(v_kind) > 0 then
            e.event_kind_id = any(v_kind) else true end
        and
            case when cardinality(v_region) > 0 then
            r.normalized_name = any(v_region) else true end
        and
            case when v_date_from is not null then
            e.starts_at >= v_date_from else true end
        and
            case when v_date_to is not null then
            e.starts_at <= v_date_to else true end
        and
            case when v_max_distance is not null and v_user_location is not null then
            st_dwithin(v_user_location, coalesce(e.location, g.location), v_max_distance) else true end
        and
            case when v_tsquery_with_prefix_matching is not null then
                v_tsquery_with_prefix_matching @@ e.tsdoc
            else true end
    ),
    filtered_events_page as (
        select community_id, event_id, group_id
        from filtered_events
        order by
            (case when v_sort_by = 'date' and v_sort_direction = 'asc' then starts_at end) asc,
            (case when v_sort_by = 'date' and v_sort_direction = 'desc' then starts_at end) desc,
            (
                case
                    when v_sort_by = 'distance'
                    and v_sort_direction = 'asc'
                    and v_user_location is not null then distance
                end
            ) asc,
            (
                case
                    when v_sort_by = 'distance'
                    and v_sort_direction = 'desc'
                    and v_user_location is not null then distance
                end
            ) desc,
            starts_at asc
        limit v_limit
        offset v_offset
    )
    select json_build_object(
        'bbox',
        (
            case when p_filters ? 'include_bbox' and (p_filters->>'include_bbox')::boolean = true then
                (
                    select
                        case when bb is not null then
                            json_build_object(
                                'ne_lat', st_ymax(bb),
                                'ne_lon', st_xmax(bb),
                                'sw_lat', st_ymin(bb),
                                'sw_lon', st_xmin(bb)
                            )
                        else null end
                    from (
                        select st_envelope(st_union(st_envelope(location::geometry))) as bb
                        from filtered_events
                    ) as filtered_events_bbox
                )
            else null end
        ),
        'events',
        (
            select coalesce(json_agg(
                get_event_summary(community_id, group_id, event_id)
            ), '[]'::json)
            from filtered_events_page
        ),
        'total',
        (
            select count(*)::bigint from filtered_events
        )
    )
    );
end
$$ language plpgsql;
