-- Returns the community groups that match the filters provided.
create or replace function search_community_groups(p_community_id uuid, p_filters jsonb)
returns setof json as $$
declare
    v_region text[];
begin
    -- Prepare filters
    if p_filters ? 'region' then
        select array_agg(lower(e::text)) into v_region
        from jsonb_array_elements_text(p_filters->'region') e;
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
        order by g.created_at desc
    ) groups;
end
$$ language plpgsql;
