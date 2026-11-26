-- verify_email verifies a user's email address using a verification code.
create or replace function verify_email(
    p_code uuid
) returns void as $$
declare
    v_consumed_user_id uuid;
    v_user_id uuid;
begin
    -- Resolve the verification code owner before locking to preserve user -> email_verification_code lock order
    select evc.user_id
    into v_user_id
    from email_verification_code evc
    where evc.email_verification_code_id = p_code;

    -- Reject codes that do not exist
    if not found then
        raise exception 'email verification failed: invalid code' using errcode = 'OCG01';
    end if;

    -- Lock the user row first to prevent deadlocks with resend flows
    perform 1
    from "user" u
    where u.user_id = v_user_id
    for update;

    -- Delete the verification code within the shared validity window and load its owner
    delete from email_verification_code
    where email_verification_code_id = p_code
    and user_id = v_user_id
    and created_at > current_timestamp - email_verification_code_ttl()
    returning user_id into v_consumed_user_id;

    -- Reject expired or concurrently consumed codes
    if v_consumed_user_id is null then
        raise exception 'email verification failed: invalid code' using errcode = 'OCG01';
    end if;

    -- Mark the user's email as verified
    update "user"
    set email_verified = true
    where user_id = v_consumed_user_id;
end;
$$ language plpgsql;
