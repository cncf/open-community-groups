-- Returns paginated group members with join date and profile/contact info visible to the viewer.
create or replace function list_group_members(
    p_group_id uuid,
    p_viewer_user_id uuid,
    p_can_manage_members boolean,
    p_filters jsonb
)
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
                u.coffee_meet_enabled,
                u.company,
                u.country,
                u.facebook_url,
                u.github_url,
                u.interests,
                u.linkedin_url,
                u.mentorship_businesses,
                u.mentorship_individuals,
                u.mentorship_note,
                u.mentorship_price,
                u.name,
                u.photo_url,
                u.phone_country_code,
                u.phone_number,
                u.substack_url,
                u.title,
                u.twitter_url,
                u.website_url,
                u.youtube_url,
                coalesce(u.provider ? 'linkedin', false) as linkedin_connected,
                phone_request.status as phone_request_status,
                coalesce(phone_requesters.requesters, '[]'::json) as phone_requesters
            from group_member gm
            join "user" u using (user_id)
            cross join filters f
            left join group_member_phone_request phone_request
                on phone_request.group_id = gm.group_id
                and phone_request.requester_user_id = p_viewer_user_id
                and phone_request.recipient_user_id = u.user_id
            left join lateral (
                select json_agg(json_build_object(
                    'user_id', requester.user_id,
                    'username', requester.username,
                    'name', requester.name
                ) order by request.created_at asc) as requesters
                from group_member_phone_request request
                join "user" requester on requester.user_id = request.requester_user_id
                where request.group_id = gm.group_id
                  and request.recipient_user_id = u.user_id
                  and request.status = 'pending'
                  and u.user_id = p_viewer_user_id
            ) phone_requesters on true
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
                    u.mentorship_note,
                    u.mentorship_price,
                    u.name,
                    u.substack_url,
                    u.title,
                    u.twitter_url,
                    u.website_url,
                    u.youtube_url,
                    case when coalesce(u.provider ? 'linkedin', false) then 'linkedin' end
                ) ilike '%' || escape_ilike_pattern(f.query) || '%' escape '\'
            )
        ),
        -- Select the paginated member list
        members as (
            select
                extract(epoch from fm.created_at)::bigint as created_at,
                fm.user_id,
                fm.email,
                fm.username,

                fm.bio,
                fm.bluesky_url,
                fm.city,
                fm.coffee_meet_enabled,
                fm.company,
                fm.country,
                fm.facebook_url,
                fm.github_url,
                fm.interests,
                fm.linkedin_url,
                fm.mentorship_businesses,
                fm.mentorship_individuals,
                fm.mentorship_note,
                fm.mentorship_price,
                fm.name,
                fm.photo_url,
                case
                    when fm.phone_number is not null and fm.phone_country_code is not null then true
                    else false
                end as has_phone_number,
                case
                    when p_can_manage_members
                         or fm.user_id = p_viewer_user_id
                         or fm.phone_request_status = 'approved'
                    then fm.phone_country_code
                    else null
                end as phone_country_code,
                case
                    when p_can_manage_members
                         or fm.user_id = p_viewer_user_id
                         or fm.phone_request_status = 'approved'
                    then fm.phone_number
                    else null
                end as phone_number,
                fm.phone_request_status,
                fm.phone_requesters,
                fm.substack_url,
                fm.title,
                fm.twitter_url,
                fm.website_url,
                fm.youtube_url,
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
