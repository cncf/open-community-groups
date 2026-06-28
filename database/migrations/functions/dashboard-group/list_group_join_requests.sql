-- Returns pending join requests for a group.
create or replace function list_group_join_requests(p_group_id uuid)
returns json as $$
    select coalesce(json_agg(json_build_object(
        'created_at', extract(epoch from gjr.created_at)::bigint,
        'user_id', u.user_id,
        'email', u.email,
        'username', u.username,

        'bio', u.bio,
        'bluesky_url', u.bluesky_url,
        'city', u.city,
        'company', u.company,
        'country', u.country,
        'facebook_url', u.facebook_url,
        'github_url', u.github_url,
        'interests', u.interests,
        'linkedin_url', u.linkedin_url,
        'linkedin_connected', coalesce(u.provider ? 'linkedin', false),
        'name', u.name,
        'photo_url', u.photo_url,
        'title', u.title,
        'twitter_url', u.twitter_url,
        'website_url', u.website_url
    ) order by gjr.created_at asc, lower(u.name) asc, lower(u.username) asc), '[]'::json)
    from group_join_request gjr
    join "user" u using (user_id)
    where gjr.group_id = p_group_id
    and gjr.status = 'pending';
$$ language sql stable;
