-- list_regions returns all regions for a community.
create or replace function list_regions(
    p_community_id uuid
)
returns json as $$
    select coalesce(json_agg(
        json_build_object(
            'region_id', r.region_id,
            'name', r.name,
            'normalized_name', r.normalized_name,
            'order', r."order"
        ) order by r."order" nulls last, r.name
    ), '[]')
    from region r
    where r.community_id = p_community_id;
$$ language sql;
