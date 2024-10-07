-- Returns the community groups that match the filters provided.
create or replace function search_community_groups(p_community_id uuid, p_filters jsonb)
returns setof json as $$
declare
    v_region text[];
    v_tsquery_with_prefix_matching tsquery;
begin
    -- Prepare filters
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

    return query select coalesce(json_agg(json_build_object(
        'city', city,
        'country', country,
        'description', description,
        'icon_url', icon_url,
        'name', name,
        'region_name', region_name,
        'slug', slug,
        'state', state
    )), '[]') as json_data
    from (
        select
            g.city,
            g.country,
            g.description,
            g.icon_url,
            g.name,
            g.slug,
            g.state,
            r.name as region_name
        from "group" g
        join region r using (region_id)
        where g.community_id = $1
        and
            case when cardinality(v_region) > 0 then
            r.normalized_name = any(v_region) else true end
        and
            case when v_tsquery_with_prefix_matching is not null then
                v_tsquery_with_prefix_matching @@ g.tsdoc
            else true end
        order by g.created_at desc
    ) groups;
end
$$ language plpgsql;
