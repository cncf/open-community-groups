-- Activates a pre-registered user after verified external-provider login.
create or replace function activate_pre_registered_user_external_provider(
    p_user_id uuid,
    p_user jsonb
)
returns json as $$
declare
    v_username text;
begin
    -- Resolve the requested username while ignoring the placeholder row
    v_username := resolve_unique_username(p_user->>'username', p_user_id);

    -- Promote the placeholder record into a regular verified user
    update "user"
    set
        auth_hash = encode(gen_random_bytes(32), 'hex'),
        email_verified = true,
        name = p_user->>'name',
        photo_url = p_user->>'photo_url',
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
