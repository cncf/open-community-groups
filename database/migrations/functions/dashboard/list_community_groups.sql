-- Returns all groups in a community for dashboard administration.
create or replace function list_community_groups(p_community_id uuid)
returns json as $$
    select coalesce(json_agg(
        get_group_summary(g.group_id)
    ), '[]')
    from (
        select g.group_id
        from "group" g
        where g.community_id = p_community_id
        order by g.name asc
    ) g;
$$ language sql;