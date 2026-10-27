-- Adds a user to the group team.
create or replace function add_group_team_member(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_user_id uuid,
    p_role text
) returns void as $$
begin
    -- Create a pending group team membership
    insert into group_team (group_id, user_id, role, accepted)
    values (p_group_id, p_user_id, p_role, false);

    -- Track the created membership
    perform insert_audit_log(
        'group_team_member_added',
        p_actor_user_id,
        'user',
        p_user_id,
        p_group_id => p_group_id,
        p_details => jsonb_build_object('role', p_role)
    );
exception
    -- Reject duplicate group team memberships
    when unique_violation then
        raise exception 'user is already a group team member' using errcode = 'OCG01';
end;
$$ language plpgsql;
