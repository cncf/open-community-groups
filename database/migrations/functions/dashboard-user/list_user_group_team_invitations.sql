-- Returns pending group team invitations for a user in a given community.
create or replace function list_user_group_team_invitations(
    p_community_id uuid,
    p_user_id uuid
) returns json as $$
    select coalesce(json_agg(row_to_json(invitation)), '[]'::json)
    from (
        select
            g.group_id,
            g.name as group_name,
            gt.role,
            extract(epoch from gt.created_at)::bigint as created_at
        from group_team gt
        join "group" g using (group_id)
        join "user" u on u.user_id = gt.user_id
        where g.community_id = p_community_id
          and gt.user_id = p_user_id
          and gt.accepted = false
          and u.community_id = p_community_id
        order by gt.created_at desc
    ) invitation;
$$ language sql;
