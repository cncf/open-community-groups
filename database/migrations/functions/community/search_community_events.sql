-- Returns the community events that match the filters provided.
create or replace function search_community_events(p_community_id uuid, p_filters jsonb)
returns table(events json, bbox json, total bigint) as $$
declare
    v_bbox geometry;
    v_date_from date := (p_filters->>'date_from');
    v_date_to date := (p_filters->>'date_to');
    v_event_category text[];
    v_group_category text[];
    v_kind text[];
    v_limit int := coalesce((p_filters->>'limit')::int, 10);
    v_max_distance real;
    v_offset int := coalesce((p_filters->>'offset')::int, 0);
    v_region text[];
    v_sort_by text := coalesce(p_filters->>'sort_by', 'date');
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
    if p_filters ? 'event_category' then
        select array_agg(lower(e::text)) into v_event_category
        from jsonb_array_elements_text(p_filters->'event_category') e;
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

    return query
    with filtered_events as (
        select
            e.canceled,
            e.description_short,
            e.ends_at,
            e.event_kind_id,
            e.logo_url,
            e.name,
            e.slug,
            e.starts_at,
            e.timezone,
            e.venue_address,
            e.venue_city,
            e.venue_name,
            g.city as group_city,
            g.country_code as group_country_code,
            g.country_name as group_country_name,
            g.location,
            g.logo_url as group_logo_url,
            g.name as group_name,
            g.slug as group_slug,
            g.state as group_state,
            gc.name as group_category_name,
            st_y(g.location::geometry) as latitude,
            st_x(g.location::geometry) as longitude,
            st_distance(g.location, v_user_location) as distance
        from event e
        join "group" g using (group_id)
        join group_category gc using (group_category_id)
        join event_category ec using (event_category_id)
        left join region r using (region_id)
        where g.community_id = p_community_id
        and g.active = true
        and e.published = true
        and
            case when v_bbox is not null then
            st_intersects(g.location, v_bbox) else true end
        and
            case when cardinality(v_event_category) > 0 then
            ec.slug = any(v_event_category) else true end
        and
            case when cardinality(v_group_category) > 0 then
            gc.normalized_name = any(v_group_category) else true end
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
            st_dwithin(v_user_location, g.location, v_max_distance) else true end
        and
            case when v_tsquery_with_prefix_matching is not null then
                v_tsquery_with_prefix_matching @@ e.tsdoc
            else true end
    )
    select
        (
            select coalesce(json_agg(json_build_object(
                'canceled', canceled,
                'kind', event_kind_id,
                'name', name,
                'slug', slug,
                'timezone', timezone,
                
                'description_short', description_short,
                'ends_at', floor(extract(epoch from ends_at)),
                'group_category_name', group_category_name,
                'group_city', group_city,
                'group_country_code', group_country_code,
                'group_country_name', group_country_name,
                'group_name', group_name,
                'group_slug', group_slug,
                'group_state', group_state,
                'latitude', latitude,
                'logo_url', coalesce(logo_url, group_logo_url),
                'longitude', longitude,
                'starts_at', floor(extract(epoch from starts_at)),
                'venue_address', venue_address,
                'venue_city', venue_city,
                'venue_name', venue_name
            )), '[]')
            from (
                select *
                from filtered_events
                order by
                    (case when v_sort_by = 'date' then starts_at end) asc,
                    (case when v_sort_by = 'distance' and v_user_location is not null then distance end) asc,
                    starts_at asc
                limit v_limit
                offset v_offset
            ) filtered_events_page
        ),
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
        (
            select count(*) from filtered_events
        );
end
$$ language plpgsql;
