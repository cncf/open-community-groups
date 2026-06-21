-- sign_up_user creates a new user and generates an email verification code if needed.
create or replace function sign_up_user(
    p_user jsonb,
    p_email_verified boolean default false
)
returns table("user" json, verification_code uuid) as $$
declare
    v_user_id uuid;
    v_username text;
    v_verification_code uuid;
begin
    -- Resolve the requested username before inserting the user
    v_username := resolve_unique_username(p_user->>'username');

    -- Insert the user with the available username
    insert into "user" (
        auth_hash,
        email,
        email_verified,
        name,
        password,
        photo_url,
        provider,
        username
    ) values (
        encode(gen_random_bytes(32), 'hex'),
        lower(p_user->>'email'),
        p_email_verified,
        p_user->>'name',
        p_user->>'password',
        p_user->>'photo_url',
        p_user->'provider',
        v_username
    )
    returning user_id into v_user_id;

    -- Generate verification code if email is not verified
    if not p_email_verified then
        insert into email_verification_code (user_id)
        values (v_user_id)
        returning email_verification_code_id into v_verification_code;
    end if;

    -- Return the user and verification code
    return query
    select
        json_strip_nulls(json_build_object(
            'auth_hash', u.auth_hash,
            'email', u.email,
            'email_verified', u.email_verified,
            'optional_notifications_enabled', u.optional_notifications_enabled,
            'name', u.name,
            'photo_url', u.photo_url,
            'provider', u.provider,
            'user_id', u.user_id,
            'username', u.username
        )),
        v_verification_code
    from "user" u
    where u.user_id = v_user_id;
end;
$$ language plpgsql;
