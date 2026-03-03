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
        where g.community_id = p_community_id
          and gt.group_id = p_group_id
          and gt.user_id = p_user_id
          and gt.accepted = true
          and case
              when p_permission = 'group.read' then gt.role in ('admin', 'events-manager', 'viewer')
              when p_permission = 'group.events.write' then gt.role in ('admin', 'events-manager')
              when p_permission = 'group.members.write' then gt.role = 'admin'
              when p_permission = 'group.settings.write' then gt.role = 'admin'
              when p_permission = 'group.sponsors.write' then gt.role = 'admin'
              when p_permission = 'group.team.write' then gt.role = 'admin'
              else false
          end
    )
    or exists (
        select 1
        from community_team ct
        join "group" g on g.community_id = ct.community_id
        where ct.community_id = p_community_id
          and g.group_id = p_group_id
          and ct.user_id = p_user_id
          and ct.accepted = true
          and case
              when p_permission = 'group.read' then ct.role in ('admin', 'groups-manager', 'viewer')
              when p_permission = 'group.events.write' then ct.role in ('admin', 'groups-manager')
              when p_permission = 'group.members.write' then ct.role in ('admin', 'groups-manager')
              when p_permission = 'group.settings.write' then ct.role in ('admin', 'groups-manager')
              when p_permission = 'group.sponsors.write' then ct.role in ('admin', 'groups-manager')
              when p_permission = 'group.team.write' then ct.role in ('admin', 'groups-manager')
              else false
          end
    );
$$ language sql;
