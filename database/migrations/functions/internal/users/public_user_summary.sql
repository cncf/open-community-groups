-- Projects the public identity of a user for embedding in listings: the
-- identifier, username and the optional profile fields shown next to a name.
create or replace function public_user_summary(p_user "user")
returns jsonb as $$
    select jsonb_strip_nulls(jsonb_build_object(
        'user_id', p_user.user_id,
        'username', p_user.username,

        'company', p_user.company,
        'name', p_user.name,
        'photo_url', p_user.photo_url,
        'title', p_user.title
    ));
$$ language sql immutable;
