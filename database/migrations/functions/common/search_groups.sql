-- Returns the groups that match the filters provided.
create or replace function search_groups(p_filters jsonb)
returns json as $$
declare
    v_bbox geometry;
    v_community_ids uuid[];
    v_group_category text[];
    v_include_inactive boolean := coalesce((p_filters->>'include_inactive')::boolean, false);
    v_limit int := coalesce((p_filters->>'limit')::int, 10);
    v_max_distance real;
    v_offset int := coalesce((p_filters->>'offset')::int, 0);
    v_region text[];
    v_sort_by text := coalesce(p_filters->>'sort_by', 'name');
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

    return (
    with filtered_groups as (
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
        join group_category gc using (group_category_id)
        left join region r using (region_id)
        where (g.active = true or v_include_inactive)
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
            else true end
    ),
    filtered_groups_page as (
        select community_id, group_id
        from filtered_groups
        order by
            (case when v_sort_by = 'date' then created_at end) desc,
            (case when v_sort_by = 'distance' and v_user_location is not null then distance end) asc,
            (case when v_sort_by = 'name' then name end) asc,
            created_at desc
        limit v_limit
        offset v_offset
    )
    select json_build_object(
        'groups',
        (
            select coalesce(json_agg(
                get_group_summary(community_id, group_id)
            ), '[]'::json)
            from filtered_groups_page
        ),
        'total',
        (
            select count(*)::bigint from filtered_groups
        ),

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
                        from filtered_groups
                    ) as filtered_groups_bbox
                )
            else null end
        )
    )
    );
end
$$ language plpgsql;
