-- Resends an email verification code for an unverified registered user after cooldown.
create or replace function resend_email_verification(
    p_email text,
    p_verification_code uuid,
    p_verification_template_data jsonb
)
returns boolean as $$
declare
    v_email text;
    v_user_id uuid;
begin
    -- Require a verification code to send the verification email
    if p_verification_code is null then
        raise exception 'verification code is required to send verification email';
    end if;

    -- Require template data to send the verification email
    if p_verification_template_data is null then
        raise exception 'verification template data is required to send verification email';
    end if;

    -- Normalize the email address
    v_email := nullif(btrim(p_email), '');

    -- Ignore blank email addresses silently
    if v_email is null then
        return false;
    end if;

    -- Lock an unverified registered user matching the email address
    select u.user_id
    into v_user_id
    from "user" u
    where lower(u.email) = lower(v_email)
    and u.registration_status = 'registered'
    and u.email_verified = false
    for update;

    -- Return silently when no unverified registered account matches
    if not found then
        return false;
    end if;

    -- Enforce the per-user cooldown when a recent verification code already exists
    if exists (
        select 1
        from email_verification_code
        where user_id = v_user_id
        and created_at > current_timestamp - auth_recovery_cooldown()
    ) then
        return false;
    end if;

    -- Cancel any superseded pending verification emails before issuing a replacement code
    with superseded as (
        select notification_id
        from notification
        where user_id = v_user_id
        and kind = 'email-verification'
        and delivery_status = 'pending'
        for update skip locked
    )
    update notification n
    set
        delivery_status = 'failed',
        error = 'email verification code superseded',
        next_delivery_attempt_at = null,
        processed_at = current_timestamp
    from superseded s
    where n.notification_id = s.notification_id;

    -- Store the new verification code and queue the verification email
    perform issue_email_verification(
        v_user_id,
        p_verification_code,
        p_verification_template_data
    );

    -- Report that a replacement verification email was issued
    return true;
end;
$$ language plpgsql;
