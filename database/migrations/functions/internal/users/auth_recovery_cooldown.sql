-- Returns the per-user cooldown window for password reset and verification resend emails.
create or replace function auth_recovery_cooldown()
returns interval as $$
    select interval '2 minutes';
$$ language sql immutable parallel safe;
