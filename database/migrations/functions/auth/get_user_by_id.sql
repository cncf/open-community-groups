-- get_user_by_id returns user information by user ID.
-- If p_include_password is true, the password field is included in the response.
create or replace function get_user_by_id(
    p_user_id uuid,
    p_include_password boolean
)
returns json as $$
    -- Build user payload with optional and computed fields
    select json_strip_nulls(json_build_object(
        -- Include core identity fields
        'auth_hash', auth_hash,
        'email', email,
        'email_verified', email_verified,
        'optional_notifications_enabled', optional_notifications_enabled,
        'name', name,
        'platform_admin', platform_admin,
        'user_id', user_id,
        'username', username,

        -- Include optional profile fields
        'bio', bio,
        'bluesky_url', bluesky_url,
        'city', city,
        'coffee_meet_enabled', coffee_meet_enabled,
        'company', company,
        'country', country,
        'facebook_url', facebook_url,
        'github_url', github_url,
        'has_password', case when password is not null then true else null end,
        'interests', interests,
        'intentional_dating_enabled', intentional_dating_enabled,
        'intentional_dating_goals', intentional_dating_goals,
        'intentional_dating_preferences', intentional_dating_preferences,
        'linkedin_url', linkedin_url,
        'mentorship_businesses', mentorship_businesses,
        'mentorship_individuals', mentorship_individuals,
        'mentorship_note', mentorship_note,
        'mentorship_price', mentorship_price,
        'password', case when p_include_password then password else null end,
        'photo_url', photo_url,
        'phone_country_code', phone_country_code,
        'phone_number', phone_number,
        'provider', provider,
        'substack_url', substack_url,
        'timezone', timezone,
        'title', title,
        'twitter_url', twitter_url,
        'website_url', website_url,
        'youtube_url', youtube_url,

        -- Include computed membership flags
        'belongs_to_any_group_team', exists (
            select 1
            from group_team gt
            where gt.user_id = u.user_id
            and gt.accepted = true
        ) or exists (
            select 1
            from alliance_team ct
            where ct.user_id = u.user_id
            and ct.accepted = true
        ),
        'belongs_to_alliance_team', exists (
            select 1
            from alliance_team ct
            where ct.user_id = u.user_id
            and ct.accepted = true
        )
    ))
    from "user" u
    where u.user_id = p_user_id;
$$ language sql;
