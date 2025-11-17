-- verify_email verifies a user's email address using a verification code.
create or replace function verify_email(
    p_code uuid
) returns void as $$
declare
    v_user_id uuid;
begin
    -- Delete the verification code and get the user_id
    -- The code must be valid and not older than 24 hours
    delete from email_verification_code
    where email_verification_code_id = p_code
    and created_at > current_timestamp - interval '1 day'
    returning user_id into v_user_id;

    -- Check if we found a valid code
    if v_user_id is null then
        raise exception 'email verification failed: invalid code';
    end if;

    -- Mark the user's email as verified
    update "user"
    set email_verified = true
    where user_id = v_user_id;
end;
$$ language plpgsql;
