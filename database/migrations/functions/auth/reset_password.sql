-- Consumes a single-use password reset token, updates the user's password, and rotates auth_hash.
create or replace function reset_password(
    p_token_hash bytea,
    p_password text
)
returns void as $$
declare
    v_consumed_user_id uuid;
    v_user_id uuid;
begin
    -- Require a 32-byte SHA-256 token digest
    if p_token_hash is null or octet_length(p_token_hash) <> 32 then
        raise exception 'password reset token hash must be 32 bytes';
    end if;

    -- Require a non-empty password hash
    if nullif(btrim(p_password), '') is null then
        raise exception 'password hash is required';
    end if;

    -- Resolve the token owner before locking to preserve user -> password_reset_token lock order
    select prt.user_id
    into v_user_id
    from password_reset_token prt
    where prt.token_hash = p_token_hash;

    -- Reject tokens that do not exist
    if not found then
        raise exception 'password reset failed: invalid or expired token' using errcode = 'OCG01';
    end if;

    -- Lock the eligible password user first to prevent deadlocks with token creation
    perform 1
    from "user" u
    where u.user_id = v_user_id
    and u.registration_status = 'registered'
    and u.email_verified = true
    and u.password is not null
    for update;

    -- Reject tokens whose owner is no longer eligible for password reset
    if not found then
        raise exception 'password reset failed: invalid or expired token' using errcode = 'OCG01';
    end if;

    -- Atomically consume the single-use token if it is still within its validity window
    delete from password_reset_token
    where token_hash = p_token_hash
    and user_id = v_user_id
    and created_at > current_timestamp - password_reset_token_ttl()
    returning user_id into v_consumed_user_id;

    -- Reject expired or concurrently consumed tokens
    if v_consumed_user_id is null then
        raise exception 'password reset failed: invalid or expired token' using errcode = 'OCG01';
    end if;

    -- Update the password hash and rotate auth_hash to invalidate active sessions
    update "user"
    set
        auth_hash = encode(gen_random_bytes(32), 'hex'),
        password = p_password
    where user_id = v_consumed_user_id;

    -- Scrub stored password-reset notification payloads now that the token is consumed
    perform purge_password_reset_notification_data(array[v_consumed_user_id]);

    -- Record the password update in the user's audit log
    perform insert_audit_log(
        'user_password_updated',
        v_consumed_user_id,
        'user',
        v_consumed_user_id,
        p_details => jsonb_build_object('via', 'password_reset')
    );
end;
$$ language plpgsql;
