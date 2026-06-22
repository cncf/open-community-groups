-- Adds a user to the alliance team.
create or replace function add_alliance_team_member(
    p_actor_user_id uuid,
    p_alliance_id uuid,
    p_user_id uuid,
    p_role text
) returns void as $$
begin
    -- Create a pending alliance team membership
    insert into alliance_team (alliance_id, user_id, accepted, role)
    values (p_alliance_id, p_user_id, false, p_role);

    -- Track the created membership
    perform insert_audit_log(
        'alliance_team_member_added',
        p_actor_user_id,
        'user',
        p_user_id,
        p_alliance_id,
        null,
        null,
        jsonb_build_object('role', p_role)
    );
exception
    when unique_violation then
        -- Reject duplicate alliance team memberships
        raise exception 'user is already a alliance team member';
end;
$$ language plpgsql;
