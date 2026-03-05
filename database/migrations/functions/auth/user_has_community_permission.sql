-- user_has_community_permission checks whether a user has a specific
-- community capability in a given community.
create or replace function user_has_community_permission(
    p_community_id uuid,
    p_user_id uuid,
    p_permission text
) returns boolean as $$
    select exists (
        select 1
        from community_team ct
        join community_role_community_permission crcp on crcp.community_role_id = ct.role
        where ct.community_id = p_community_id
          and ct.user_id = p_user_id
          and ct.accepted = true
          and crcp.community_permission_id = p_permission
    );
$$ language sql;
