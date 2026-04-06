-- Adds a new region to a community.
create or replace function add_region(
    p_actor_user_id uuid,
    p_community_id uuid,
    p_region jsonb
)
returns uuid as $$
declare
    v_region_id uuid;
begin
    -- Insert the region record
    insert into region (
        community_id,
        name
    ) values (
        p_community_id,
        p_region->>'name'
    )
    returning region_id into v_region_id;

    -- Track the created region
    perform insert_audit_log(
        'region_added',
        p_actor_user_id,
        'region',
        v_region_id,
        p_community_id
    );

    return v_region_id;
exception when unique_violation then
    raise exception 'region already exists';
end;
$$ language plpgsql;
