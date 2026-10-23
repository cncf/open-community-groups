-- Returns the accepted team members of a group in team order.
create or replace function list_group_organizers(p_group_id uuid)
returns json as $$
    select coalesce(json_agg(json_strip_nulls(json_build_object(
        'user_id', u.user_id,
        'username', u.username,

        'bio', u.bio,
        'bluesky_url', u.bluesky_url,
        'company', u.company,
        'facebook_url', u.facebook_url,
        'github_url', u.github_url,
        'linkedin_url', u.linkedin_url,
        'name', u.name,
        'photo_url', u.photo_url,
        'provider', get_public_user_provider(u.provider),
        'title', u.title,
        'twitter_url', u.twitter_url,
        'website_url', u.website_url
    )) order by gt."order" nulls last, u.name), '[]')
    from group_team gt
    join "user" u using (user_id)
    where gt.group_id = p_group_id
    and gt.accepted = true;
$$ language sql stable;
