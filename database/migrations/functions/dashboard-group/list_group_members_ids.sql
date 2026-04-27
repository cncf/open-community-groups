-- Returns all group members user ids.
create or replace function list_group_members_ids(p_group_id uuid)
returns uuid[] as $$
    select coalesce(array_agg(gm.user_id order by gm.user_id asc), array[]::uuid[])
    from group_member gm
    join "user" u using (user_id)
    where gm.group_id = p_group_id
    and u.email_verified = true;
$$ language sql;
