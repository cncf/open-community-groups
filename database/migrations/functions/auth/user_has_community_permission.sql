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
        where ct.community_id = p_community_id
          and ct.user_id = p_user_id
          and ct.accepted = true
          and case
              when p_permission = 'community.read' then ct.role in ('admin', 'groups-manager', 'viewer')
              when p_permission = 'community.groups.write' then ct.role in ('admin', 'groups-manager')
              when p_permission = 'community.settings.write' then ct.role = 'admin'
              when p_permission = 'community.taxonomy.write' then ct.role = 'admin'
              when p_permission = 'community.team.write' then ct.role = 'admin'
              else false
          end
    );
$$ language sql;
