-- Projects the public profile of a user read by the Rust User type: identifier,
-- username and the optional profile and social fields, omitting absent ones.
create or replace function public_user_profile(p_user "user")
returns jsonb as $$
    select jsonb_strip_nulls(jsonb_build_object(
        'user_id', p_user.user_id,
        'username', p_user.username,

        'bio', p_user.bio,
        'bluesky_url', p_user.bluesky_url,
        'company', p_user.company,
        'facebook_url', p_user.facebook_url,
        'github_url', p_user.github_url,
        'linkedin_url', p_user.linkedin_url,
        'name', p_user.name,
        'photo_url', p_user.photo_url,
        'provider', get_public_user_provider(p_user.provider),
        'title', p_user.title,
        'twitter_url', p_user.twitter_url,
        'website_url', p_user.website_url
    ));
$$ language sql stable;
