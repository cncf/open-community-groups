-- Updates a group team member's role.
create or replace function update_group_team_member_role(
    p_group_id uuid,
    p_user_id uuid,
    p_role text
) returns void as $$
begin
    update group_team
    set role = p_role
    where group_id = p_group_id
      and user_id = p_user_id;

    if not found then
        raise exception 'user is not a group team member';
    end if;
end;
$$ language plpgsql;

