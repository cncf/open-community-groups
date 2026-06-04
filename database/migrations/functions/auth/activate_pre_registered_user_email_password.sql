-- Activates a pre-registered user after password signup and generates an email verification code.
create or replace function activate_pre_registered_user_email_password(
    p_user jsonb
)
returns table("user" json, verification_code uuid) as $$
declare
    v_user_id uuid;
    v_username text;
    v_verification_code uuid;
begin
    -- Lock the placeholder user if this email was pre-registered
    select u.user_id
    into v_user_id
    from "user" u
    where lower(u.email) = lower(p_user->>'email')
    and u.registration_status = 'pre-registered'
    for update;

    if not found then
        return;
    end if;

    -- Resolve the requested username while ignoring the placeholder row
    v_username := resolve_unique_username(p_user->>'username', v_user_id);

    -- Promote the placeholder row while keeping email verification pending
    update "user"
    set
        auth_hash = encode(gen_random_bytes(32), 'hex'),
        email_verified = false,
        name = p_user->>'name',
        password = p_user->>'password',
        provider = p_user->'provider',
        registration_status = 'registered',
        username = v_username
    where user_id = v_user_id
    and registration_status = 'pre-registered';

    if not found then
        raise exception 'pre-registered user not found';
    end if;

    -- Create/refresh email verification code for the activated user
    insert into email_verification_code (user_id)
    values (v_user_id)
    on conflict (user_id) do update
    set created_at = current_timestamp
    returning email_verification_code_id into v_verification_code;

    return query
    select
        json_strip_nulls(json_build_object(
            'auth_hash', u.auth_hash,
            'email', u.email,
            'email_verified', u.email_verified,
            'optional_notifications_enabled', u.optional_notifications_enabled,
            'name', u.name,
            'provider', u.provider,
            'user_id', u.user_id,
            'username', u.username
        )),
        v_verification_code
    from "user" u
    where u.user_id = v_user_id;
end;
$$ language plpgsql;
