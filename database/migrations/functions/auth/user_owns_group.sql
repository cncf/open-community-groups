-- user_owns_group returns whether a user is part of the group team.
create or replace function user_owns_group(
    p_user_id uuid,
    p_group_id uuid
) returns boolean as $$
    select exists (
        select 1
        from group_team
        where user_id = p_user_id
        and group_id = p_group_id
    );
$$ language sql;