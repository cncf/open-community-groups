-- Adds a user to the community team.
create or replace function add_community_team_member(
    p_community_id uuid,
    p_user_id uuid,
    p_role text
) returns void as $$
begin
    -- Create a pending community team membership
    insert into community_team (community_id, user_id, accepted, role)
    values (p_community_id, p_user_id, false, p_role);
exception
    when unique_violation then
        -- Reject duplicate community team memberships
        raise exception 'user is already a community team member';
end;
$$ language plpgsql;
