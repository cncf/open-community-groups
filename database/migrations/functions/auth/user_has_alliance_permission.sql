-- user_has_alliance_permission checks whether a user has a specific
-- alliance capability in a given alliance.
create or replace function user_has_alliance_permission(
    p_alliance_id uuid,
    p_user_id uuid,
    p_permission text
) returns boolean as $$
    select exists (
        select 1
        from alliance_team ct
        join alliance_role_alliance_permission crcp on crcp.alliance_role_id = ct.role
        where ct.alliance_id = p_alliance_id
          and ct.user_id = p_user_id
          and ct.accepted = true
          and crcp.alliance_permission_id = p_permission
    );
$$ language sql;
