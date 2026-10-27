-- Stores a user's email verification code, replacing any previous one, and
-- queues the verification email.
create or replace function issue_email_verification(
    p_user_id uuid,
    p_verification_code uuid,
    p_verification_template_data jsonb
)
returns uuid as $$
declare
    v_verification_code uuid;
begin
    -- Require a verification code to send the verification email
    if p_verification_code is null then
        raise exception 'verification code is required to send verification email';
    end if;

    -- Require template data to send the verification email
    if p_verification_template_data is null then
        raise exception 'verification template data is required to send verification email';
    end if;

    -- Store the verification code, replacing any previous one
    insert into email_verification_code (email_verification_code_id, user_id)
    values (p_verification_code, p_user_id)
    on conflict (user_id) do update
    set
        created_at = current_timestamp,
        email_verification_code_id = excluded.email_verification_code_id
    returning email_verification_code_id into v_verification_code;

    -- Queue the verification email
    perform enqueue_notification(
        'email-verification',
        p_verification_template_data,
        '[]'::jsonb,
        array[p_user_id]
    );

    -- Return the stored verification code
    return v_verification_code;
end;
$$ language plpgsql;
