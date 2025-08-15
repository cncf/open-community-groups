-- sign_up_user creates a new user.
create or replace function sign_up_user(
    p_community_id uuid,
    p_user jsonb
)
returns json as $$
    insert into "user" (
        auth_hash,
        community_id,
        email,
        email_verified,
        first_name,
        username
    ) values (
        gen_random_bytes(32),
        p_community_id,
        p_user->>'email',
        coalesce((p_user->>'email_verified')::boolean, false),
        p_user->>'first_name',
        p_user->>'username'
    )
    returning json_strip_nulls(json_build_object(
        'email', email,
        'email_verified', email_verified,
        'first_name', first_name,
        'user_id', user_id,
        'username', username
    ));
$$ language sql;