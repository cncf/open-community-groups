-- Updates a region in a alliance.
create or replace function update_region(
    p_actor_user_id uuid,
    p_alliance_id uuid,
    p_region_id uuid,
    p_region jsonb
)
returns void as $$
begin
    -- Ensure the target region exists in the selected alliance
    perform 1
    from region r
    where r.alliance_id = p_alliance_id
      and r.region_id = p_region_id;

    if not found then
        raise exception 'region not found';
    end if;

    -- Update the region record
    update region set
        name = p_region->>'name'
    where alliance_id = p_alliance_id
      and region_id = p_region_id;

    -- Track the updated region
    perform insert_audit_log(
        'region_updated',
        p_actor_user_id,
        'region',
        p_region_id,
        p_alliance_id
    );
exception when unique_violation then
    raise exception 'region already exists';
end;
$$ language plpgsql;
