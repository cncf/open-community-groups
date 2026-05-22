-- Activates a pre-registered user after verified external-provider login.
create or replace function activate_pre_registered_user_external_provider(
    p_user_id uuid,
    p_user jsonb
)
returns json as $$
declare
    v_base_username text;
    v_suffix int;
    v_username text;
    v_username_exists boolean;
begin
    -- Generate a unique username using the provider-provided username
    v_base_username := p_user->>'username';
    v_username := v_base_username;

    select exists(
        select 1
        from "user"
        where username = v_username
        and user_id <> p_user_id
    ) into v_username_exists;

    if v_username_exists then
        for v_suffix in 2..99 loop
            v_username := v_base_username || v_suffix;

            select exists(
                select 1
                from "user"
                where username = v_username
                and user_id <> p_user_id
            ) into v_username_exists;

            exit when not v_username_exists;
        end loop;

        if v_username_exists then
            raise exception 'unable to generate unique username: all variants from % to %99 are taken', v_base_username, v_base_username;
        end if;
    end if;

    -- Promote the placeholder record into a regular verified user
    update "user"
    set
        auth_hash = encode(gen_random_bytes(32), 'hex'),
        email_verified = true,
        name = p_user->>'name',
        provider = p_user->'provider',
        registration_status = 'registered',
        username = v_username
    where user_id = p_user_id
    and registration_status = 'pre-registered';

    if not found then
        raise exception 'pre-registered user not found';
    end if;

    return get_user_by_id(p_user_id, false);
end;
$$ language plpgsql;
