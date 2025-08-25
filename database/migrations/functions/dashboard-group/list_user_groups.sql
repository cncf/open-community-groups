-- Returns all groups where the user is a team member.
-- If the user is a community team member, returns all groups in the community.
create or replace function list_user_groups(p_user_id uuid)
returns json as $$
    select coalesce(json_agg(
        get_group_summary(g.group_id)
        order by (get_group_summary(g.group_id)::jsonb->>'name') asc
    ), '[]')
    from (
        -- Get all groups if user is a community team member
        select g.group_id
        from "group" g
        join "user" u on u.user_id = p_user_id
        where exists (
            select 1
            from community_team ct
            where ct.user_id = p_user_id
            and ct.community_id = u.community_id
        )
        and g.community_id = u.community_id
        and g.deleted = false
        
        union
        
        -- Get only groups where user is a team member if not a community team member
        select g.group_id
        from "group" g
        join group_team gt using (group_id)
        join "user" u on u.user_id = p_user_id
        where gt.user_id = p_user_id
        and g.deleted = false
        and not exists (
            select 1
            from community_team ct
            where ct.user_id = p_user_id
            and ct.community_id = u.community_id
        )
    ) g;
$$ language sql;