-- Returns all pending group team invitations for a user.
create or replace function list_user_group_team_invitations(p_user_id uuid)
returns json as $$
    select coalesce(json_agg(row_to_json(invitation)), '[]'::json)
    from (
        select
            c.name as community_name,
            g.group_id,
            g.name as group_name,
            gt.role,

            extract(epoch from gt.created_at)::bigint as created_at
        from group_team gt
        join "group" g using (group_id)
        join community c using (community_id)
        where gt.user_id = p_user_id
          and gt.accepted = false
        order by gt.created_at desc
    ) invitation;
$$ language sql;
