-- Creates a password reset token for an eligible user and queues the reset email.
create or replace function create_password_reset_token(
    p_email text,
    p_token_hash bytea,
    p_template_data jsonb
)
returns boolean as $$
declare
    v_email text;
    v_user_id uuid;
begin
    -- Require a 32-byte SHA-256 token digest
    if p_token_hash is null or octet_length(p_token_hash) <> 32 then
        raise exception 'password reset token hash must be 32 bytes';
    end if;

    -- Require template data for the reset notification
    if p_template_data is null then
        raise exception 'password reset template data is required';
    end if;

    -- Normalize the email address
    v_email := nullif(btrim(p_email), '');

    -- Ignore blank email addresses silently
    if v_email is null then
        return false;
    end if;

    -- Lock an eligible verified password user matching the email address
    select u.user_id
    into v_user_id
    from "user" u
    where lower(u.email) = lower(v_email)
    and u.registration_status = 'registered'
    and u.email_verified = true
    and u.password is not null
    for update;

    -- Return silently when no eligible password account matches
    if not found then
        return false;
    end if;

    -- Enforce the per-user cooldown when a recent token already exists
    if exists (
        select 1
        from password_reset_token
        where user_id = v_user_id
        and created_at > current_timestamp - auth_recovery_cooldown()
    ) then
        return false;
    end if;

    -- Scrub any superseded password-reset notification payloads before issuing a new token
    perform purge_password_reset_notification_data(array[v_user_id]);

    -- Store the hashed token, replacing any previous token for this user
    insert into password_reset_token (token_hash, user_id)
    values (p_token_hash, v_user_id)
    on conflict (user_id) do update
    set
        created_at = current_timestamp,
        token_hash = excluded.token_hash;

    -- Queue the password reset email
    perform enqueue_notification(
        'password-reset',
        p_template_data,
        '[]'::jsonb,
        array[v_user_id]
    );

    -- Report that a password reset token was issued
    return true;
end;
$$ language plpgsql;
