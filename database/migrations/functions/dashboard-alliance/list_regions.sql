-- list_regions returns all regions for a alliance.
create or replace function list_regions(
    p_alliance_id uuid
)
returns json as $$
    select coalesce(json_agg(
        json_build_object(
            'groups_count', coalesce(stats.groups_count, 0),
            'region_id', r.region_id,
            'name', r.name,
            'normalized_name', r.normalized_name,
            'order', r."order"
        ) order by r."order" nulls last, r.name
    ), '[]')
    from region r
    left join (
        select
            g.region_id,
            count(*) as groups_count
        from region r_filter
        join "group" g on g.region_id = r_filter.region_id
        where r_filter.alliance_id = p_alliance_id
        group by g.region_id
    ) stats using (region_id)
    where r.alliance_id = p_alliance_id;
$$ language sql;
