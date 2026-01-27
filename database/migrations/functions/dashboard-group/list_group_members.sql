-- Returns paginated group members with join date and basic profile info.
create or replace function list_group_members(p_group_id uuid, p_filters jsonb)
returns json as $$
    with
        filters as (
            select
                (p_filters->>'limit')::int as limit_value,
                (p_filters->>'offset')::int as offset_value
        ),
        members as (
            select
                extract(epoch from gm.created_at)::bigint as created_at,
                u.username,

                u.company,
                u.name,
                u.photo_url,
                u.title
            from group_member gm
            join "user" u using (user_id)
            where gm.group_id = p_group_id
            order by (u.name is not null) desc, lower(u.name) asc, lower(u.username) asc, u.user_id asc
            offset (select offset_value from filters)
            limit (select limit_value from filters)
        ),
        totals as (
            select count(*)::int as total
            from group_member gm
            where gm.group_id = p_group_id
        ),
        members_json as (
            select coalesce(json_agg(row_to_json(members)), '[]'::json) as members
            from members
        )
    select json_build_object(
        'members', members_json.members,
        'total', totals.total
    )
    from totals, members_json;
$$ language sql;
