-- Updates an existing sponsor in the group.
create or replace function update_group_sponsor(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_group_sponsor_id uuid,
    p_sponsor jsonb
)
returns void as $$
begin
    -- Update the sponsor for the group
    update group_sponsor set
        featured = coalesce((p_sponsor->>'featured')::boolean, false),
        logo_url = p_sponsor->>'logo_url',
        name = p_sponsor->>'name',
        website_url = nullif(p_sponsor->>'website_url', '')
    where group_sponsor_id = p_group_sponsor_id
    and group_id = p_group_id;

    if found then
        -- Track the sponsor update
        perform insert_audit_log(
            'group_sponsor_updated',
            p_actor_user_id,
            'group_sponsor',
            p_group_sponsor_id,
            (select community_id from "group" where group_id = p_group_id),
            p_group_id
        );
    end if;
end;
$$ language plpgsql;
