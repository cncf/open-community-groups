-- Returns all pending alliance team invitations for a user.
create or replace function list_user_alliance_team_invitations(p_user_id uuid)
returns json as $$
    select coalesce(json_agg(row_to_json(invitation)), '[]'::json)
    from (
        select
            ct.alliance_id,
            c.name as alliance_name,
            ct.role,

            extract(epoch from ct.created_at)::bigint as created_at
        from alliance_team ct
        join alliance c using (alliance_id)
        where ct.user_id = p_user_id
          and ct.accepted = false
        order by ct.created_at desc
    ) invitation;
$$ language sql;
