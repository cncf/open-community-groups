-- Activates a pre-registered user after password signup and generates an email verification code.
create or replace function activate_pre_registered_user_email_password(
    p_user jsonb
)
returns table("user" json, verification_code uuid) as $$
declare
    v_base_username text;
    v_suffix int;
    v_username text;
    v_username_exists boolean;
    v_user_id uuid;
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

    -- Generate a unique username using the user-provided username
    v_base_username := p_user->>'username';
    v_username := v_base_username;

    select exists(
        select 1
        from "user"
        where username = v_username
        and user_id <> v_user_id
    ) into v_username_exists;

    if v_username_exists then
        for v_suffix in 2..99 loop
            v_username := v_base_username || v_suffix;

            select exists(
                select 1
                from "user"
                where username = v_username
                and user_id <> v_user_id
            ) into v_username_exists;

            exit when not v_username_exists;
        end loop;

        if v_username_exists then
            raise exception 'unable to generate unique username: all variants from % to %99 are taken', v_base_username, v_base_username;
        end if;
    end if;

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
