-- Returns whether a password reset token hash exists and is still within its validity window.
create or replace function has_valid_password_reset_token(
    p_token_hash bytea
)
returns boolean as $$
    select exists (
        select 1
        from password_reset_token prt
        join "user" u using (user_id)
        where prt.token_hash = p_token_hash
        and prt.created_at > current_timestamp - password_reset_token_ttl()
        and u.registration_status = 'registered'
        and u.email_verified = true
        and u.password is not null
    );
$$ language sql stable;
