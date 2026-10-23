-- Deletes a region from a community when not in use.
create or replace function delete_region(
    p_actor_user_id uuid,
    p_community_id uuid,
    p_region_id uuid
)
returns void as $$
declare
    v_name text;
begin
    -- Lock the region and snapshot its name for the audit row
    select r.name
    into v_name
    from region r
    where r.community_id = p_community_id
      and r.region_id = p_region_id
    for update of r;

    -- Reject regions outside the selected community
    if not found then
        raise exception 'region not found' using errcode = 'OCG01';
    end if;

    -- Reject regions still used by any groups, including deleted ones
    if exists (
        select 1
        from "group" g
        where g.region_id = p_region_id
    ) then
        raise exception 'cannot delete region in use by groups' using errcode = 'OCG01';
    end if;

    -- Delete the region record
    delete from region r
    where r.community_id = p_community_id
      and r.region_id = p_region_id;

    -- Track the deletion
    perform insert_audit_log(
        'region_deleted',
        p_actor_user_id,
        'region',
        p_region_id,
        p_community_id,
        null,
        null,
        jsonb_build_object('name', v_name)
    );
end;
$$ language plpgsql;
