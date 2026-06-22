-- user_has_group_permission checks whether a user has a specific
-- group capability for a group in a given alliance.
create or replace function user_has_group_permission(
    p_alliance_id uuid,
    p_group_id uuid,
    p_user_id uuid,
    p_permission text
) returns boolean as $$
    select exists (
        select 1
        from group_team gt
        join "group" g on g.group_id = gt.group_id
        join alliance c on c.alliance_id = g.alliance_id
        join group_role_group_permission grp on grp.group_role_id = gt.role
        where g.alliance_id = p_alliance_id
          and g.deleted = false
          and gt.group_id = p_group_id
          and gt.user_id = p_user_id
          and gt.accepted = true
          and grp.group_permission_id = p_permission
          and (
              p_permission <> 'group.team.write'
              or c.group_team_management_restricted = false
          )
    )
    or exists (
        select 1
        from alliance_team ct
        join "group" g on g.alliance_id = ct.alliance_id
        join alliance_role_group_permission crgp on crgp.alliance_role_id = ct.role
        where ct.alliance_id = p_alliance_id
          and g.deleted = false
          and g.group_id = p_group_id
          and ct.user_id = p_user_id
          and ct.accepted = true
          and crgp.group_permission_id = p_permission
    );
$$ language sql;
