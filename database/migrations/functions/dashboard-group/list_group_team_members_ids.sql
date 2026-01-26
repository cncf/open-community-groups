-- Returns all accepted group team member user ids.
create or replace function list_group_team_members_ids(p_group_id uuid)
returns json as $$
    select coalesce(json_agg(member.user_id), '[]'::json)
    from (
        select gt.user_id
        from group_team gt
        join "user" u using (user_id)
        where gt.group_id = p_group_id
        and gt.accepted = true
        and u.email_verified = true
        order by gt.user_id asc
    ) member;
$$ language sql;
