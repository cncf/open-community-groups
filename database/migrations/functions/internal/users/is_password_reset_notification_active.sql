-- Returns whether a password-reset notification still corresponds to an active, unexpired reset token.
create or replace function is_password_reset_notification_active(
    p_user_id uuid,
    p_notification_created_at timestamptz
)
returns boolean as $$
    select exists (
        select 1
        from password_reset_token prt
        where prt.user_id = p_user_id
        and prt.created_at > current_timestamp - password_reset_token_ttl()
        and prt.created_at <= p_notification_created_at
    );
$$ language sql stable;
