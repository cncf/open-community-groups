-- Updates a region in a community.
create or replace function update_region(
    p_community_id uuid,
    p_region_id uuid,
    p_region jsonb
)
returns void as $$
begin
    -- Ensure the target region exists in the selected community
    perform 1
    from region r
    where r.community_id = p_community_id
      and r.region_id = p_region_id;

    if not found then
        raise exception 'region not found';
    end if;

    -- Update the region record
    update region set
        name = p_region->>'name'
    where community_id = p_community_id
      and region_id = p_region_id;
exception when unique_violation then
    raise exception 'region already exists';
end;
$$ language plpgsql;
