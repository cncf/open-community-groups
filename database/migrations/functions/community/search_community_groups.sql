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
    if p_filters ? 'distance' and p_filters ? 'latitude' and p_filters ? 'longitude' then
        v_max_distance := (p_filters->>'distance')::real;
        v_user_location := st_setsrid(st_makepoint((p_filters->>'longitude')::real, (p_filters->>'latitude')::real), 4326);
    end if;
    if p_filters ? 'group_category' then
        select array_agg(lower(e::text)) into v_group_category
        from jsonb_array_elements_text(p_filters->'group_category') e;
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
            g.city,
            g.country_code,
            g.country_name,
            g.created_at,
            case
                when
                    g.description like '%PLEASE ADD A DESCRIPTION HERE%'
                    or g.description like '%DESCRIPTION GOES HERE%'
                    or g.description like '%ADD DESCRIPTION HERE%'
                    or g.description like '%PLEASE UPDATE THE BELOW DESCRIPTION%'
                    or g.description like '%PLEASE UPDATE THE DESCRIPTION HERE%'
                then null else
                    replace(regexp_replace(substring(g.description for 500), E'<[^>]+>', '', 'gi'), '&nbsp;', ' ')
            end as description,
            g.location,
            g.logo_url,
            g.name,
            g.slug,
            g.state,
            gc.name as category_name,
            r.name as region_name,
            st_y(g.location::geometry) as latitude,
            st_x(g.location::geometry) as longitude,
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
            select coalesce(json_agg(json_build_object(
                'category_name', category_name,
                'city', city,
                'country_code', country_code,
                'country_name', country_name,
                'created_at', floor(extract(epoch from created_at)),
                'description', description,
                'latitude', latitude,
                'logo_url', logo_url,
                'longitude', longitude,
                'name', name,
                'region_name', region_name,
                'slug', slug,
                'state', state
            )), '[]')
            from (
                select *
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
                    select json_build_object(
                        'ne_lat', st_ymax(bb),
                        'ne_lon', st_xmax(bb),
                        'sw_lat', st_ymin(bb),
                        'sw_lon', st_xmin(bb)
                    )
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
