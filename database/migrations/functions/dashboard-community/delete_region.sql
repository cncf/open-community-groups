-- Deletes a region from a community when not in use.
create or replace function delete_region(
    p_community_id uuid,
    p_region_id uuid
)
returns void as $$
declare
    v_groups_count bigint;
begin
    -- Ensure the region exists in the selected community
    perform 1
    from region r
    where r.community_id = p_community_id
      and r.region_id = p_region_id;

    if not found then
        raise exception 'region not found';
    end if;

    -- Block deletion when groups still reference this region
    select count(*)
    into v_groups_count
    from "group" g
    where g.region_id = p_region_id;

    if v_groups_count > 0 then
        raise exception 'cannot delete region in use by groups';
    end if;

    -- Delete the region record
    delete from region r
    where r.community_id = p_community_id
      and r.region_id = p_region_id;
end;
$$ language plpgsql;
