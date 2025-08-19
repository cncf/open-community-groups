-- sign_up_user creates a new user and generates an email verification code if needed.
create or replace function sign_up_user(
    p_community_id uuid,
    p_user jsonb,
    p_email_verified boolean default false
)
returns table("user" json, verification_code uuid) as $$
declare
    v_user_id uuid;
    v_verification_code uuid;
begin
    
    -- Insert the user
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
        p_user->>'username'
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
            'password', u.password,
            'user_id', u.user_id,
            'username', u.username
        )),
        v_verification_code
    from "user" u
    where u.user_id = v_user_id;
end;
$$ language plpgsql;