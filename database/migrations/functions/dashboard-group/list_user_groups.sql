-- Returns all groups where the user is a team member, grouped by alliance.
-- If the user is a alliance team member, returns all groups in that alliance.
create or replace function list_user_groups(p_user_id uuid)
returns json as $$
    with user_groups as (
        -- Get all groups in alliances where the user is a alliance team member
        select g.group_id, g.alliance_id
        from "group" g
        where exists (
            select 1
            from alliance_team ct
            where ct.user_id = p_user_id
            and ct.alliance_id = g.alliance_id
            and ct.accepted = true
        )
        and g.deleted = false

        union

        -- Get groups where user is a group team member
        select g.group_id, g.alliance_id
        from "group" g
        join group_team gt using (group_id)
        where gt.user_id = p_user_id
        and gt.accepted = true
        and g.deleted = false
    ),
    groups_with_data as (
        select
            ug.alliance_id,
            c.name as alliance_name,
            json_strip_nulls(json_build_object(
                'active', g.active,
                'group_id', g.group_id,
                'name', g.name,
                'slug', g.slug,

                'slug_pretty', g.slug_pretty
            )) as group_json
        from user_groups ug
        join alliance c using (alliance_id)
        join "group" g using (group_id)
    ),
    groups_by_alliance as (
        select
            alliance_id,
            alliance_name,
            coalesce(json_agg(
                group_json order by group_json->>'name' asc
            ), '[]') as groups
        from groups_with_data
        group by alliance_id, alliance_name
    )
    select coalesce(json_agg(
        json_build_object(
            'alliance', get_alliance_summary(alliance_id),
            'groups', groups
        )
        order by alliance_name asc
    ), '[]')
    from groups_by_alliance;
$$ language sql;
