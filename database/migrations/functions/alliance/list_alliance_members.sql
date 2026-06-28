-- Returns paginated alliance members across all groups with basic profile info.
create or replace function list_alliance_members(p_alliance_id uuid, p_filters jsonb)
returns json as $$
    with
        filters as (
            select
                (p_filters->>'limit')::int as limit_value,
                (p_filters->>'offset')::int as offset_value,
                nullif(trim(p_filters->>'query'), '') as query
        ),
        member_groups as (
            select
                gm.user_id,
                array_agg(distinct g.name order by g.name) as group_names
            from group_member gm
            join "group" g using (group_id)
            where g.alliance_id = p_alliance_id
              and g.active = true
              and g.deleted = false
            group by gm.user_id
        ),
        filtered_members as (
            select
                mg.group_names,
                u.user_id,
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
                u.mentorship_businesses,
                u.mentorship_individuals,
                u.mentorship_note,
                u.mentorship_price,
                u.name,
                u.photo_url,
                u.substack_url,
                u.title,
                u.twitter_url,
                u.website_url,
                u.youtube_url,
                coalesce(u.provider ? 'linkedin', false) as linkedin_connected
            from member_groups mg
            join "user" u using (user_id)
            cross join filters f
            where u.email_verified = true
              and u.registration_status = 'registered'
              and (
                  f.query is null
                  or concat_ws(
                      ' ',
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
                      array_to_string(mg.group_names, ' '),
                      case when u.mentorship_individuals then 'individual mentorship individuals mentor' end,
                      case when u.mentorship_businesses then 'business mentorship businesses mentor' end,
                      case when coalesce(u.provider ? 'linkedin', false) then 'linkedin' end
                  ) ilike '%' || escape_ilike_pattern(f.query) || '%' escape '\'
              )
        ),
        members as (
            select
                fm.group_names,
                fm.user_id,
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
                fm.mentorship_businesses,
                fm.mentorship_individuals,
                fm.mentorship_note,
                fm.mentorship_price,
                fm.name,
                fm.photo_url,
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
        totals as (
            select count(*)::int as total
            from filtered_members
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
