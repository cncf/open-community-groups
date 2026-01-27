-- Returns paginated group team members.
create or replace function list_group_team_members(p_group_id uuid, p_filters jsonb)
returns json as $$
    with
        filters as (
            select
                (p_filters->>'limit')::int as limit_value,
                (p_filters->>'offset')::int as offset_value
        ),
        members as (
            select
                gt.accepted,
                u.user_id,
                u.username,

                u.company,
                u.name,
                u.photo_url,
                gt.role,
                u.title
            from group_team gt
            join "user" u using (user_id)
            where gt.group_id = p_group_id
            order by coalesce(lower(u.name), lower(u.username)) asc, u.user_id asc
            offset (select offset_value from filters)
            limit (select limit_value from filters)
        ),
        totals as (
            select
                count(*)::int as total,
                count(*) filter (where gt.accepted)::int as approved_total
            from group_team gt
            where gt.group_id = p_group_id
        ),
        members_json as (
            select coalesce(json_agg(row_to_json(members)), '[]'::json) as members
            from members
        )
    select json_build_object(
        'approved_total', totals.approved_total,
        'members', members_json.members,
        'total', totals.total
    )
    from totals, members_json;
$$ language sql;
