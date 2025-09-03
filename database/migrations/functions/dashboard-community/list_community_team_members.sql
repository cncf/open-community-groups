-- Returns all community team members.
create or replace function list_community_team_members(p_community_id uuid)
returns json as $$
    select coalesce(json_agg(row_to_json(member)), '[]'::json)
    from (
        select
            u.user_id,
            u.username,

            u.name,
            u.photo_url
        from community_team ct
        join "user" u on u.user_id = ct.user_id and u.community_id = ct.community_id
        where ct.community_id = p_community_id
        order by coalesce(lower(u.name), lower(u.username)) asc
    ) member;
$$ language sql;

