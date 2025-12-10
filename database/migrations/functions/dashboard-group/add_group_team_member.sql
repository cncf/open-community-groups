-- Adds a user to the group team.
create or replace function add_group_team_member(
    p_group_id uuid,
    p_user_id uuid,
    p_role text
) returns void as $$
begin
    insert into group_team (group_id, user_id, role, accepted)
    values (p_group_id, p_user_id, p_role, false);
exception
    when unique_violation then
        raise exception 'user is already a group team member';
end;
$$ language plpgsql;
