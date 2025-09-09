-- Returns all group members user ids.
create or replace function list_group_members_ids(p_group_id uuid)
returns json as $$
    select coalesce(json_agg(member.user_id), '[]'::json)
    from (
        select user_id
        from group_member
        where group_id = p_group_id
        order by user_id asc
    ) member;
$$ language sql;
