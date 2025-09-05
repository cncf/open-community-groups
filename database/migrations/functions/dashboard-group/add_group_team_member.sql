-- Adds a user to the group team. Ensures user and group belong to the same community.
create or replace function add_group_team_member(
    p_group_id uuid,
    p_user_id uuid,
    p_role text
) returns void as $$
begin
    begin
        insert into group_team (group_id, user_id, role, accepted)
        select p_group_id, p_user_id, p_role, false
        from "user" u
        join "group" g on g.group_id = p_group_id
        where u.user_id = p_user_id and u.community_id = g.community_id;
    exception
        when unique_violation then
            raise exception 'user is already a group team member';
    end;
end;
$$ language plpgsql;
