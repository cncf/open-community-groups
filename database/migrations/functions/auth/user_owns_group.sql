-- user_owns_group returns whether a user is part of the group team or the
-- community team.
create or replace function user_owns_group(
    p_community_id uuid,
    p_group_id uuid,
    p_user_id uuid
) returns boolean as $$
    select exists (
        select 1
        from group_team gt
        join "group" g on g.group_id = gt.group_id
        where g.community_id = p_community_id
        and gt.group_id = p_group_id
        and gt.user_id = p_user_id
    )
    or exists (
        select 1
        from community_team ct
        join "group" g on g.community_id = ct.community_id
        where ct.community_id = p_community_id
        and g.group_id = p_group_id
        and ct.user_id = p_user_id
    );
$$ language sql;