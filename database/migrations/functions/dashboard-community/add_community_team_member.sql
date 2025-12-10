-- Adds a user to the community team.
create or replace function add_community_team_member(
    p_community_id uuid,
    p_user_id uuid
) returns void as $$
begin
    insert into community_team (community_id, user_id, accepted)
    values (p_community_id, p_user_id, false);
exception
    when unique_violation then
        raise exception 'user is already a community team member';
end;
$$ language plpgsql;
