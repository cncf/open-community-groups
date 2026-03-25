-- Adds a user to the community team.
create or replace function add_community_team_member(
    p_actor_user_id uuid,
    p_community_id uuid,
    p_user_id uuid,
    p_role text
) returns void as $$
begin
    -- Create a pending community team membership
    insert into community_team (community_id, user_id, accepted, role)
    values (p_community_id, p_user_id, false, p_role);

    -- Track the created membership
    perform insert_audit_log(
        'community_team_member_added',
        p_actor_user_id,
        'user',
        p_user_id,
        p_community_id,
        null,
        null,
        jsonb_build_object('role', p_role)
    );
exception
    when unique_violation then
        -- Reject duplicate community team memberships
        raise exception 'user is already a community team member';
end;
$$ language plpgsql;
