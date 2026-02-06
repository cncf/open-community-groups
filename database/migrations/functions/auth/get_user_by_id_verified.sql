-- get_user_by_id_verified returns a verified user by ID.
create or replace function get_user_by_id_verified(
    p_user_id uuid
)
returns json as $$
    select get_user_by_id(
        (
            select u.user_id
            from "user" u
            where u.user_id = p_user_id
            and u.email_verified = true
        ),
        false
    );
$$ language sql;
