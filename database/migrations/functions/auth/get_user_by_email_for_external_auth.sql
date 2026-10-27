-- Returns a registered or pre-registered user by email for external authentication.
create or replace function get_user_by_email_for_external_auth(
    p_email text
)
returns json as $$
    select external_auth_user_json(u)
    from "user" u
    where lower(u.email) = lower(p_email)
    and (
        (u.registration_status = 'registered' and u.email_verified = true)
        or u.registration_status = 'pre-registered'
    );
$$ language sql stable;
