-- Returns a registered or pre-registered user by email for external authentication.
create or replace function get_user_by_email_for_external_auth(
    p_email text
)
returns json as $$
    select (
        get_user_by_id(u.user_id, false)::jsonb
        || jsonb_build_object(
            'name', coalesce(u.name, ''),
            'registration_status', u.registration_status
        )
    )::json
    from "user" u
    where lower(u.email) = lower(p_email)
    and (
        (u.registration_status = 'registered' and u.email_verified = true)
        or u.registration_status = 'pre-registered'
    );
$$ language sql;
