-- Returns the community events that match the filters provided.
create or replace function search_community_events(p_community_id uuid, p_filters jsonb)
returns setof json as $$
declare
    v_kind text[];
    v_region text[];
    v_date_from date := (p_filters->>'date_from');
    v_date_to date := (p_filters->>'date_to');
    v_tsquery_with_prefix_matching tsquery;
begin
    -- Prepare filters
    if p_filters ? 'kind' then
        select array_agg(e::text) into v_kind
        from jsonb_array_elements_text(p_filters->'kind') e;
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
    select coalesce(json_agg(json_build_object(
        'cancelled', cancelled,
        'city', city,
        'country', country,
        'description', description,
        'icon_url', icon_url,
        'kind_id', event_kind_id,
        'postponed', postponed,
        'slug', event_slug,
        'starts_at', floor(extract(epoch from starts_at)),
        'state', state,
        'title', title,
        'venue', venue,
        'group_name', group_name,
        'group_slug', group_slug
    )), '[]') as json_data
    from (
        select
            e.cancelled,
            e.city,
            e.country,
            e.description,
            e.event_kind_id,
            e.icon_url,
            e.postponed,
            e.slug as event_slug,
            e.starts_at,
            e.state,
            e.title,
            e.venue,
            g.name as group_name,
            g.slug as group_slug
        from event e
        join "group" g using (group_id)
        join region r using (region_id)
        where g.community_id = $1
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
            case when v_tsquery_with_prefix_matching is not null then
                v_tsquery_with_prefix_matching @@ e.tsdoc
            else true end
        order by e.starts_at asc
    ) events;
end
$$ language plpgsql;
