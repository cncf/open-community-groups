-- sign_up_user creates a new user and generates an email verification code if needed.
create or replace function sign_up_user(
    p_community_id uuid,
    p_user jsonb
)
returns table("user" json, verification_code uuid) as $$
declare
    v_user_id uuid;
    v_email_verified boolean;
    v_verification_code uuid;
begin
    -- Get email_verified status
    v_email_verified := coalesce((p_user->>'email_verified')::boolean, false);
    
    -- Insert the user
    insert into "user" (
        auth_hash,
        community_id,
        email,
        email_verified,
        name,
        username
    ) values (
        gen_random_bytes(32),
        p_community_id,
        p_user->>'email',
        v_email_verified,
        p_user->>'name',
        p_user->>'username'
    )
    returning user_id into v_user_id;
    
    -- Generate verification code if email is not verified
    if not v_email_verified then
        insert into email_verification_code (user_id)
        values (v_user_id)
        returning email_verification_code_id into v_verification_code;
    end if;
    
    -- Return the user and verification code
    return query
    select 
        json_strip_nulls(json_build_object(
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