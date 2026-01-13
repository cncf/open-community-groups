-- user_owns_groups_in_community returns whether a user is part of any group
-- team in the given community or the community team.
create or replace function user_owns_groups_in_community(
    p_community_id uuid,
    p_user_id uuid
) returns boolean as $$
    select exists (
        select 1
        from group_team gt
        join "group" g on g.group_id = gt.group_id
        where g.community_id = p_community_id
        and gt.user_id = p_user_id
        and gt.accepted = true
        and gt.role = 'organizer'
    )
    or exists (
        select 1
        from community_team ct
        where ct.community_id = p_community_id
        and ct.user_id = p_user_id
        and ct.accepted = true
    );
$$ language sql;
