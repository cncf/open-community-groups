-- Deletes a user from the community team.
create or replace function delete_community_team_member(
    p_community_id uuid,
    p_user_id uuid
) returns void as $$
begin
    delete from community_team
    where community_id = p_community_id
      and user_id = p_user_id;

    -- Raise error if no membership was removed.
    if not found then
        raise exception 'user is not a community team member';
    end if;
end;
$$ language plpgsql;
