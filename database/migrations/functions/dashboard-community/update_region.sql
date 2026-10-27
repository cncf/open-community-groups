-- Updates a region in a community.
create or replace function update_region(
    p_actor_user_id uuid,
    p_community_id uuid,
    p_region_id uuid,
    p_region jsonb
)
returns void as $$
begin
    -- Update the region record
    update region set
        name = p_region->>'name'
    where community_id = p_community_id
      and region_id = p_region_id;

    -- Reject targets outside the selected community
    if not found then
        raise exception 'region not found' using errcode = 'OCG01';
    end if;

    -- Track the updated region
    perform insert_audit_log(
        'region_updated',
        p_actor_user_id,
        'region',
        p_region_id,
        p_community_id
    );
exception
    -- Translate duplicate region names
    when unique_violation then
        raise exception 'region already exists' using errcode = 'OCG01';
end;
$$ language plpgsql;
