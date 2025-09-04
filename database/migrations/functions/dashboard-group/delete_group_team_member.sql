-- Deletes a user from the group team.
create or replace function delete_group_team_member(
    p_group_id uuid,
    p_user_id uuid
) returns void as $$
begin
    delete from group_team
    where group_id = p_group_id
      and user_id = p_user_id;

    -- Raise error if no membership was removed.
    if not found then
        raise exception 'user is not a group team member';
    end if;
end;
$$ language plpgsql;

