-- Returns all groups where the user is a team member.
create or replace function list_user_groups(p_user_id uuid)
returns json as $$
    select coalesce(json_agg(
        get_group_summary(g.group_id)
    ), '[]')
    from (
        select g.group_id
        from "group" g
        join group_team gt using (group_id)
        where gt.user_id = p_user_id
        and g.deleted = false
        order by g.name asc
    ) g;
$$ language sql;