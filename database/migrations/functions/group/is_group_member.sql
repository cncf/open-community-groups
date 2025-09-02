-- Check if a user is a member of a group.
create or replace function is_group_member(
    p_community_id uuid,
    p_group_id uuid,
    p_user_id uuid
) returns boolean as $$
    select exists (
        select 1
        from group_member gm
        join "group" g using (group_id)
        where g.community_id = p_community_id
        and gm.group_id = p_group_id
        and gm.user_id = p_user_id
        and g.active = true
    );
$$ language sql;