-- Adds a new sponsor to the group.
create or replace function add_group_sponsor(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_sponsor jsonb
)
returns uuid as $$
declare
    v_group_sponsor_id uuid;
begin
    -- Insert the sponsor for the group
    insert into group_sponsor (
        group_id,
        logo_url,
        name,

        website_url
    ) values (
        p_group_id,
        p_sponsor->>'logo_url',
        p_sponsor->>'name',

        p_sponsor->>'website_url'
    )
    returning group_sponsor_id into v_group_sponsor_id;

    -- Track the sponsor creation
    perform insert_audit_log(
        'group_sponsor_added',
        p_actor_user_id,
        'group_sponsor',
        v_group_sponsor_id,
        (select community_id from "group" where group_id = p_group_id),
        p_group_id
    );

    return v_group_sponsor_id;
end;
$$ language plpgsql;
