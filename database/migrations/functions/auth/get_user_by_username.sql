-- get_user_by_username returns a verified user with password by username.
create or replace function get_user_by_username(
    p_username text
)
returns json as $$
    select get_user_by_id(
        (
            select u.user_id
            from "user" u
            where u.username = p_username
            and u.email_verified = true
            and u.password is not null
        ),
        true
    );
$$ language sql;
