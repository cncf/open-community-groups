-- Adds a user to the community team. Ensures user belongs to the community.
create or replace function add_community_team_member(
    p_community_id uuid,
    p_user_id uuid
) returns void as $$
begin
    begin
        insert into community_team (community_id, user_id, accepted)
        select p_community_id, p_user_id, false
        from "user" u
        where u.user_id = p_user_id and u.community_id = p_community_id;
    exception
        when unique_violation then
            raise exception 'user is already a community team member';
    end;
end;
$$ language plpgsql;
