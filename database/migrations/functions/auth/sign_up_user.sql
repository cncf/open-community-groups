-- sign_up_user creates a new user and generates an email verification code if needed.
create or replace function sign_up_user(
    p_community_id uuid,
    p_user jsonb,
    p_email_verified boolean default false
)
returns table("user" json, verification_code uuid) as $$
declare
    v_username text;
    v_base_username text;
    v_suffix int;
    v_username_exists boolean;
    v_user_id uuid;
    v_verification_code uuid;
begin
    -- Get the base username
    v_base_username := p_user->>'username';
    v_username := v_base_username;

    -- Check if username exists in the community
    select exists(
        select 1 from "user"
        where username = v_username
        and community_id = p_community_id
    ) into v_username_exists;

    -- If username exists, try with numeric suffixes from 2 to 99
    if v_username_exists then
        for v_suffix in 2..99 loop
            v_username := v_base_username || v_suffix;
            select exists(
                select 1 from "user"
                where username = v_username
                and community_id = p_community_id
            ) into v_username_exists;

            exit when not v_username_exists;
        end loop;

        -- If still exists after trying all suffixes, raise error
        if v_username_exists then
            raise exception 'unable to generate unique username: all variants from % to %99 are taken', v_base_username, v_base_username;
        end if;
    end if;

    -- Insert the user with the available username
    insert into "user" (
        auth_hash,
        community_id,
        email,
        email_verified,
        name,
        password,
        username
    ) values (
        encode(gen_random_bytes(32), 'hex'),
        p_community_id,
        p_user->>'email',
        p_email_verified,
        p_user->>'name',
        p_user->>'password',
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
            'name', u.name,
            'user_id', u.user_id,
            'username', u.username
        )),
        v_verification_code
    from "user" u
    where u.user_id = v_user_id;
end;
$$ language plpgsql;
