-- Returns all groups where the user is a team member, grouped by community.
-- If the user is a community team member, returns all groups in that community.
create or replace function list_user_groups(p_user_id uuid)
returns json as $$
    with user_groups as (
        -- Get all groups in communities where the user is a community team member
        select g.group_id, g.community_id
        from "group" g
        where exists (
            select 1
            from community_team ct
            where ct.user_id = p_user_id
            and ct.community_id = g.community_id
            and ct.accepted = true
        )
        and g.deleted = false

        union

        -- Get groups where user is a group team member
        select g.group_id, g.community_id
        from "group" g
        join group_team gt using (group_id)
        where gt.user_id = p_user_id
        and gt.accepted = true
        and g.deleted = false
    ),
    groups_with_data as (
        select
            ug.community_id,
            c.name as community_name,
            json_build_object(
                'active', g.active,
                'group_id', g.group_id,
                'name', g.name,
                'slug', g.slug
            ) as group_json
        from user_groups ug
        join community c using (community_id)
        join "group" g using (group_id)
    ),
    groups_by_community as (
        select
            community_id,
            community_name,
            coalesce(json_agg(
                group_json order by group_json->>'name' asc
            ), '[]') as groups
        from groups_with_data
        group by community_id, community_name
    )
    select coalesce(json_agg(
        json_build_object(
            'community', get_community_summary(community_id),
            'groups', groups
        )
        order by community_name asc
    ), '[]')
    from groups_by_community;
$$ language sql;
