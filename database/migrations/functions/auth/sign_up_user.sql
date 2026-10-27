-- sign_up_user creates a new user and stores an email verification code if needed.
create or replace function sign_up_user(
    p_user jsonb,
    p_email_verified boolean default false,
    p_verification_code uuid default null,
    p_verification_template_data jsonb default null
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
        provider,
        username
    ) values (
        encode(gen_random_bytes(32), 'hex'),
        lower(p_user->>'email'),
        p_email_verified,
        p_user->>'name',
        p_user->>'password',
        p_user->'provider',
        v_username
    )
    returning user_id into v_user_id;

    -- Issue the verification email when the email is not verified
    if not p_email_verified then
        v_verification_code := issue_email_verification(
            v_user_id,
            p_verification_code,
            p_verification_template_data
        );
    end if;

    -- Return the user and verification code
    return query
    select get_user_by_id(v_user_id, false), v_verification_code;
end;
$$ language plpgsql;
