-- Updates the featured flag for an existing sponsor in the group.
create or replace function update_group_sponsor_featured(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_group_sponsor_id uuid,
    p_featured bool
)
returns void as $$
begin
    -- Update the sponsor featured flag for the group
    update group_sponsor set
        featured = p_featured
    where group_id = p_group_id
    and group_sponsor_id = p_group_sponsor_id;

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
