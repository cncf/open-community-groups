-- Returns all accepted group team member user ids.
create or replace function list_group_team_members_ids(p_group_id uuid)
returns uuid[] as $$
    select coalesce(array_agg(gt.user_id order by gt.user_id asc), array[]::uuid[])
    from group_team gt
    join "user" u using (user_id)
    where gt.group_id = p_group_id
    and gt.accepted = true
    and u.email_verified = true;
$$ language sql;
