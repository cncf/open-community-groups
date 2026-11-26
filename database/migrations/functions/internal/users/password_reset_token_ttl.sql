-- Returns the validity window for password reset tokens.
create or replace function password_reset_token_ttl()
returns interval as $$
    select interval '1 hour';
$$ language sql immutable parallel safe;
