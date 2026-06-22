-- Returns paginated group members with join date and basic profile info.
create or replace function list_group_members(p_group_id uuid, p_filters jsonb)
returns json as $$
    with
        -- Parse pagination filters
        filters as (
            select
                (p_filters->>'limit')::int as limit_value,
                (p_filters->>'offset')::int as offset_value,
                nullif(trim(p_filters->>'query'), '') as query
        ),
        -- Filter members before pagination so totals reflect the search query
        filtered_members as (
            select
                gm.created_at,
                u.user_id,
                u.email,
                u.username,
                u.bio,
                u.bluesky_url,
                u.city,
                u.company,
                u.country,
                u.facebook_url,
                u.github_url,
                u.interests,
                u.linkedin_url,
                u.name,
                u.photo_url,
                u.title,
                u.twitter_url,
                u.website_url,
                coalesce(u.provider ? 'linkedin', false) as linkedin_connected
            from group_member gm
            join "user" u using (user_id)
            cross join filters f
            where gm.group_id = p_group_id
            and (
                f.query is null
                or concat_ws(
                    ' ',
                    u.email,
                    u.username,
                    u.bio,
                    u.bluesky_url,
                    u.city,
                    u.company,
                    u.country,
                    u.facebook_url,
                    u.github_url,
                    array_to_string(u.interests, ' '),
                    u.linkedin_url,
                    u.name,
                    u.title,
                    u.twitter_url,
                    u.website_url,
                    case when coalesce(u.provider ? 'linkedin', false) then 'linkedin' end
                ) ilike '%' || escape_ilike_pattern(f.query) || '%' escape '\'
            )
        ),
        -- Select the paginated member list
        members as (
            select
                extract(epoch from fm.created_at)::bigint as created_at,
                fm.email,
                fm.username,

                fm.bio,
                fm.bluesky_url,
                fm.city,
                fm.company,
                fm.country,
                fm.facebook_url,
                fm.github_url,
                fm.interests,
                fm.linkedin_url,
                fm.name,
                fm.photo_url,
                fm.title,
                fm.twitter_url,
                fm.website_url,
                fm.linkedin_connected
            from filtered_members fm
            order by (fm.name is not null) desc, lower(fm.name) asc, lower(fm.username) asc, fm.user_id asc
            offset (select offset_value from filters)
            limit (select limit_value from filters)
        ),
        -- Count total members before pagination
        totals as (
            select count(*)::int as total
            from filtered_members
        ),
        -- Render members as JSON
        members_json as (
            select coalesce(json_agg(row_to_json(members)), '[]'::json) as members
            from members
        )
    -- Build final payload
    select json_build_object(
        'members', members_json.members,
        'total', totals.total
    )
    from totals, members_json;
$$ language sql;
