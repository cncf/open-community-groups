-- Adds a new region to a alliance.
create or replace function add_region(
    p_actor_user_id uuid,
    p_alliance_id uuid,
    p_region jsonb
)
returns uuid as $$
declare
    v_region_id uuid;
begin
    -- Insert the region record
    insert into region (
        alliance_id,
        name
    ) values (
        p_alliance_id,
        p_region->>'name'
    )
    returning region_id into v_region_id;

    -- Track the created region
    perform insert_audit_log(
        'region_added',
        p_actor_user_id,
        'region',
        v_region_id,
        p_alliance_id
    );

    return v_region_id;
exception when unique_violation then
    raise exception 'region already exists';
end;
$$ language plpgsql;
