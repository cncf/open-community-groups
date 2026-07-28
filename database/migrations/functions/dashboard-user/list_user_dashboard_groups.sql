-- Returns paginated groups where the user is a member or accepted team member.
create or replace function list_user_dashboard_groups(p_user_id uuid, p_filters jsonb)
returns json as $$
    with
        -- Collect the user's membership and accepted team relationships
        relationship_rows as (
            select
                gm.group_id,
                true as is_member,
                false as is_team_member,
                gm.created_at as joined_at
            from group_member gm
            where gm.user_id = p_user_id

            union all

            select
                gt.group_id,
                false as is_member,
                true as is_team_member,
                gt.created_at as joined_at
            from group_team gt
            where gt.accepted = true
            and gt.user_id = p_user_id
        ),
        -- Aggregate duplicate relationships for visible groups
        group_rows as (
            select
                g.community_id,
                g.group_id,
                bool_or(rr.is_member) as is_member,
                bool_or(rr.is_team_member) as is_team_member,
                min(rr.joined_at) as joined_at,
                g.name
            from relationship_rows rr
            join "group" g using (group_id)
            join community c using (community_id)
            where c.active = true
            and g.active = true
            and g.deleted = false
            group by g.community_id, g.group_id, g.name
        ),
        -- Select the requested page in stable name order
        group_rows_page as (
            select
                gr.community_id,
                gr.group_id,
                gr.is_member,
                gr.is_team_member,
                gr.joined_at,
                gr.name
            from group_rows gr
            order by gr.name asc, gr.group_id asc
            offset (p_filters->>'offset')::int
            limit (p_filters->>'limit')::int
        )
    -- Build the paginated response payload
    select json_build_object(
        'groups',
        (
            select coalesce(
                json_agg(
                    json_build_object(
                        'group', get_group_summary(grp.community_id, grp.group_id),
                        'is_member', grp.is_member,
                        'is_team_member', grp.is_team_member,
                        'joined_at', floor(extract(epoch from grp.joined_at))
                    )
                    order by grp.name asc, grp.group_id asc
                ),
                '[]'::json
            )
            from group_rows_page grp
        ),
        'total',
        (select count(*)::int from group_rows)
    );
$$ language sql;
