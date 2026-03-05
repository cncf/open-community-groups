-- user_has_group_permission checks whether a user has a specific
-- group capability for a group in a given community.
create or replace function user_has_group_permission(
    p_community_id uuid,
    p_group_id uuid,
    p_user_id uuid,
    p_permission text
) returns boolean as $$
    select exists (
        select 1
        from group_team gt
        join "group" g on g.group_id = gt.group_id
        join group_role_group_permission grp on grp.group_role_id = gt.role
        where g.community_id = p_community_id
          and g.deleted = false
          and gt.group_id = p_group_id
          and gt.user_id = p_user_id
          and gt.accepted = true
          and grp.group_permission_id = p_permission
    )
    or exists (
        select 1
        from community_team ct
        join "group" g on g.community_id = ct.community_id
        join community_role_group_permission crgp on crgp.community_role_id = ct.role
        where ct.community_id = p_community_id
          and g.deleted = false
          and g.group_id = p_group_id
          and ct.user_id = p_user_id
          and ct.accepted = true
          and crgp.group_permission_id = p_permission
    );
$$ language sql;
