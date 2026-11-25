-- Returns the validity window for email verification codes.
create or replace function email_verification_code_ttl()
returns interval as $$
    select interval '1 day';
$$ language sql immutable parallel safe;
