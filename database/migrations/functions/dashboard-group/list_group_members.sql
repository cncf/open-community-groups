-- Returns all group members with join date and basic profile info.
create or replace function list_group_members(p_group_id uuid)
returns json as $$
    select coalesce(json_agg(row_to_json(member)), '[]'::json)
    from (
        select
            extract(epoch from gm.created_at)::bigint as created_at,
            u.username,

            u.company,
            u.name,
            u.photo_url,
            u.title
        from group_member gm
        join "user" u using (user_id)
        where gm.group_id = p_group_id
        order by coalesce(lower(u.name), lower(u.username)) asc
    ) member;
$$ language sql;
