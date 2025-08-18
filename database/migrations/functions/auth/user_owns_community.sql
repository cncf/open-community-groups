-- user_owns_community returns whether a user is part of the community team.
create or replace function user_owns_community(
    p_user_id uuid,
    p_community_id uuid
) returns boolean as $$
    select exists (
        select 1
        from community_team
        where user_id = p_user_id
        and community_id = p_community_id
    );
$$ language sql;