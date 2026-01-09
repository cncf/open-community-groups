-- get_user_by_id returns user information by user ID.
-- If p_include_password is true, the password field is included in the response.
create or replace function get_user_by_id(
    p_user_id uuid,
    p_include_password boolean
)
returns json as $$
    select json_strip_nulls(json_build_object(
        'auth_hash', auth_hash,
        'email', email,
        'email_verified', email_verified,
        'name', name,
        'user_id', user_id,
        'username', username,

        'bio', bio,
        'city', city,
        'company', company,
        'country', country,
        'facebook_url', facebook_url,
        'has_password', case when password is not null then true else null end,
        'interests', interests,
        'linkedin_url', linkedin_url,
        'password', case when p_include_password then password else null end,
        'photo_url', photo_url,
        'timezone', timezone,
        'title', title,
        'twitter_url', twitter_url,
        'website_url', website_url,

        'belongs_to_any_group_team', exists (
            select 1
            from group_team gt
            where gt.user_id = u.user_id
            and gt.accepted = true
        ) or exists (
            select 1
            from community_team ct
            where ct.user_id = u.user_id
            and ct.accepted = true
        ),
        'belongs_to_community_team', exists (
            select 1
            from community_team ct
            where ct.user_id = u.user_id
            and ct.accepted = true
        )
    ))
    from "user" u
    where u.user_id = p_user_id;
$$ language sql;
