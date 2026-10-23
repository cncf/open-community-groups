-- Activates a pre-registered user after password signup and stores an email verification code.
create or replace function activate_pre_registered_user_email_password(
    p_user jsonb,
    p_verification_code uuid,
    p_verification_template_data jsonb
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

    -- Return no rows when the email was not pre-registered
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

    -- Reject placeholders that were activated concurrently
    if not found then
        raise exception 'pre-registered user not found' using errcode = 'OCG01';
    end if;

    -- Issue the verification email for the activated user
    v_verification_code := issue_email_verification(
        v_user_id,
        p_verification_code,
        p_verification_template_data
    );

    -- Return the activated user and verification code
    return query
    select get_user_by_id(v_user_id, false), v_verification_code;
end;
$$ language plpgsql;
