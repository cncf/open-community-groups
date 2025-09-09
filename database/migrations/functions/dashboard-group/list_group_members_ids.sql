-- Returns all group members user ids.
create or replace function list_group_members_ids(p_group_id uuid)
returns json as $$
    select coalesce(json_agg(member.user_id), '[]'::json)
    from (
        select gm.user_id
        from group_member gm
        join "user" u using (user_id)
        where gm.group_id = p_group_id
        and u.email_verified = true
        order by gm.user_id asc
    ) member;
$$ language sql;
