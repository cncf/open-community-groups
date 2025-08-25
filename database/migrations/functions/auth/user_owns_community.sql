-- user_owns_community returns whether a user is part of the community team.
create or replace function user_owns_community(
    p_community_id uuid,
    p_user_id uuid
) returns boolean as $$
    select exists (
        select 1
        from community_team
        where community_id = p_community_id
        and user_id = p_user_id
    );
$$ language sql;