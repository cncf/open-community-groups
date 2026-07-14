-- Returns all active communities with at least one active group.
create or replace function list_communities()
returns json as $$
    select coalesce(json_agg(
        get_community_summary(community_id) order by display_name
    ), '[]')
    from community c
    where c.active = true
    and exists (
        select 1
        from "group" g
        where g.community_id = c.community_id
        and g.active = true
        and g.deleted = false
    );
$$ language sql;
