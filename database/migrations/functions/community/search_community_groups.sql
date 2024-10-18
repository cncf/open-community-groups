-- Returns the community groups that match the filters provided.
create or replace function search_community_groups(p_community_id uuid, p_filters jsonb)
returns table(groups json, total bigint) as $$
declare
    v_distance real;
    v_limit int := coalesce((p_filters->>'limit')::int, 10);
    v_offset int := coalesce((p_filters->>'offset')::int, 0);
    v_region text[];
    v_tsquery_with_prefix_matching tsquery;
    v_user_location geography;
begin
    -- Prepare filters
    if p_filters ? 'distance' and p_filters ? 'latitude' and p_filters ? 'longitude' then
        v_distance := (p_filters->>'distance')::real;
        v_user_location := st_setsrid(st_makepoint((p_filters->>'longitude')::real, (p_filters->>'latitude')::real), 4326);
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
            g.country,
            g.created_at,
            g.description,
            g.icon_url,
            g.name,
            g.slug,
            g.state,
            r.name as region_name
        from "group" g
        join region r using (region_id)
        where g.community_id = p_community_id
        and
            case when v_distance is not null and v_user_location is not null then
            st_dwithin(v_user_location, g.location, v_distance) else true end
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
                'city', city,
                'country', country,
                'description', description,
                'icon_url', icon_url,
                'name', name,
                'region_name', region_name,
                'slug', slug,
                'state', state
            )), '[]')
            from (
                select *
                from filtered_groups
                order by created_at desc
                limit v_limit
                offset v_offset
            ) filtered_groups_page
        ),
        (
            select count(*) from filtered_groups
        );
end
$$ language plpgsql;
