-- get_user_by_id returns user information by user ID.
create or replace function get_user_by_id(p_user_id uuid)
returns json as $$
    select json_strip_nulls(json_build_object(
        'email', email,
        'email_verified', email_verified,
        'name', name,
        'user_id', user_id,
        'username', username
    ))
    from "user"
    where user_id = p_user_id;
$$ language sql;