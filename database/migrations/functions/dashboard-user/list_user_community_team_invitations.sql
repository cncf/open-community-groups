-- Returns all pending community team invitations for a user.
create or replace function list_user_community_team_invitations(p_user_id uuid)
returns json as $$
    select coalesce(json_agg(row_to_json(invitation)), '[]'::json)
    from (
        select
            ct.community_id,
            c.name as community_name,

            extract(epoch from ct.created_at)::bigint as created_at
        from community_team ct
        join community c using (community_id)
        where ct.user_id = p_user_id
          and ct.accepted = false
        order by ct.created_at desc
    ) invitation;
$$ language sql;
