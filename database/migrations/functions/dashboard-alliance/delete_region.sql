-- Deletes a region from a alliance when not in use.
create or replace function delete_region(
    p_actor_user_id uuid,
    p_alliance_id uuid,
    p_region_id uuid
)
returns void as $$
declare
    v_groups_count bigint;
    v_name text;
begin
    -- Ensure the region exists in the selected alliance, snapshotting its
    -- name so the audit row remains readable after deletion
    select r.name
    into v_name
    from region r
    where r.alliance_id = p_alliance_id
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
    where r.alliance_id = p_alliance_id
      and r.region_id = p_region_id;

    -- Track the deletion
    perform insert_audit_log(
        'region_deleted',
        p_actor_user_id,
        'region',
        p_region_id,
        p_alliance_id,
        null,
        null,
        jsonb_build_object('name', v_name)
    );
end;
$$ language plpgsql;
