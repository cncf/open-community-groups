-- get_user_by_email returns a verified user by email.
create or replace function get_user_by_email(
    p_email text
)
returns json as $$
    select get_user_by_id(
        (
            select u.user_id
            from "user" u
            where lower(u.email) = lower(p_email)
            and u.email_verified = true
        ),
        false
    );
$$ language sql;
