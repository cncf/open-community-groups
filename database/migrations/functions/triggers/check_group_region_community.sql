-- Rejects groups whose region belongs to another community.
create or replace function check_group_region_community()
returns trigger as $$
declare
    v_region_community_id uuid;
begin
    -- Allow groups without a region
    if new.region_id is null then
        return new;
    end if;

    -- Resolve the community that owns the region
    select community_id into v_region_community_id
    from region
    where region_id = new.region_id;

    -- Reject regions from another community
    if v_region_community_id is distinct from new.community_id then
        raise exception 'region not found in community' using errcode = 'OCG01';
    end if;

    -- Return the validated group row
    return new;
end;
$$ language plpgsql;
