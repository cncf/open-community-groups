-- Projects a group region as the JSON read by the server group models; null
-- when the group has no region.
create or replace function group_region_json(p_region region)
returns json as $$
    select case when p_region.region_id is not null then
        json_build_object(
            'region_id', p_region.region_id,
            'name', p_region.name,
            'normalized_name', p_region.normalized_name,
            'order', p_region."order"
        )
    end;
$$ language sql stable;
