-- Returns paginated community team members.
create or replace function list_community_team_members(p_community_id uuid, p_filters jsonb)
returns json as $$
    with
        -- Parse pagination filters
        filters as (
            select
                (p_filters->>'limit')::int as limit_value,
                (p_filters->>'offset')::int as offset_value
        ),
        -- Select the paginated member list
        members as (
            select
                ct.accepted,
                u.user_id,
                u.username,

                u.company,
                u.name,
                u.photo_url,
                u.title
            from community_team ct
            join "user" u on u.user_id = ct.user_id
            where ct.community_id = p_community_id
            order by coalesce(lower(u.name), lower(u.username)) asc, u.user_id asc
            offset (select offset_value from filters)
            limit (select limit_value from filters)
        ),
        -- Count totals for all and accepted members
        totals as (
            select
                count(*)::int as total,
                count(*) filter (where ct.accepted)::int as approved_total
            from community_team ct
            where ct.community_id = p_community_id
        ),
        -- Render members as JSON
        members_json as (
            select coalesce(json_agg(row_to_json(members)), '[]'::json) as members
            from members
        )
    -- Build final payload
    select json_build_object(
        'approved_total', totals.approved_total,
        'members', members_json.members,
        'total', totals.total
    )
    from totals, members_json;
$$ language sql;
