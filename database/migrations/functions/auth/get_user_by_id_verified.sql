-- get_user_by_id_verified returns a verified user by ID.
-- Uses PL/pgSQL so each connection caches its plan instead of planning the
-- SQL-language body on every authenticated request.
create or replace function get_user_by_id_verified(
    p_user_id uuid
)
returns json as $$
begin
    -- Build the user payload only for a verified, registered user
    return get_user_by_id(
        (
            select u.user_id
            from "user" u
            where u.user_id = p_user_id
            and u.email_verified = true
            and u.registration_status = 'registered'
        ),
        false
    );
end;
$$ language plpgsql stable;
