-- Returns all group team members.
create or replace function list_group_team_members(p_group_id uuid)
returns json as $$
    select coalesce(json_agg(row_to_json(member)), '[]'::json)
    from (
        select
            gt.accepted,
            u.user_id,
            u.username,

            u.company,
            u.name,
            u.photo_url,
            gt.role,
            u.title
        from group_team gt
        join "user" u using (user_id)
        where gt.group_id = p_group_id
        order by coalesce(lower(u.name), lower(u.username)) asc
    ) member;
$$ language sql;
