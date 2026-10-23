-- Returns the user payload used by external authentication, with an empty name
-- default and the registration status.
create or replace function external_auth_user_json(p_user "user")
returns json as $$
    select (
        get_user_by_id(p_user.user_id, false)::jsonb
        || jsonb_build_object(
            'name', coalesce(p_user.name, ''),
            'registration_status', p_user.registration_status
        )
    )::json;
$$ language sql stable;
