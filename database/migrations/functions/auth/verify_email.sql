-- verify_email verifies a user's email address using a verification code.
create or replace function verify_email(
    p_code uuid
) returns void as $$
declare
    v_user_id uuid;
begin
    -- Delete the verification code within the shared validity window and load its owner
    delete from email_verification_code
    where email_verification_code_id = p_code
    and created_at > current_timestamp - email_verification_code_ttl()
    returning user_id into v_user_id;

    -- Check if we found a valid code
    if v_user_id is null then
        raise exception 'email verification failed: invalid code' using errcode = 'OCG01';
    end if;

    -- Mark the user's email as verified
    update "user"
    set email_verified = true
    where user_id = v_user_id;
end;
$$ language plpgsql;
