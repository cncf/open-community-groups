-- Returns the community groups that match the filters provided.
create or replace function search_community_groups(p_community_id uuid, p_filters jsonb)
returns table(groups json, bbox json, total bigint) as $$
declare
    v_bbox geometry;
    v_group_category text[];
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
    if p_filters ? 'group_category' then
        select array_agg(lower(e::text)) into v_group_category
        from jsonb_array_elements_text(p_filters->'group_category') e;
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
    with filtered_groups as (
        select
            g.group_id,
            g.created_at,
            g.location,
            st_distance(g.location, v_user_location) as distance
        from "group" g
        join group_category gc using (group_category_id)
        left join region r using (region_id)
        where g.community_id = p_community_id
        and g.active = true
        and
            case when v_bbox is not null then
            st_intersects(g.location, v_bbox) else true end
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
            else true end
    )
    select
        (
            select coalesce(json_agg(
                format_group_description(get_group_detailed(group_id))
            ), '[]')
            from (
                select group_id
                from filtered_groups
                order by
                    (case when v_sort_by = 'date' then created_at end) desc,
                    (case when v_sort_by = 'distance' and v_user_location is not null then distance end) asc,
                    created_at desc
                limit v_limit
                offset v_offset
            ) filtered_groups_page
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
                        from filtered_groups
                    ) as filtered_groups_bbox
                )
            else null end
        ),
        (
            select count(*) from filtered_groups
        );
end
$$ language plpgsql;
