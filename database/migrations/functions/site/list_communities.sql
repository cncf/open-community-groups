-- Returns a list of all active communities with at least one group and one event.
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
    )
    and exists (
        select 1
        from event e
        join "group" g using (group_id)
        where g.community_id = c.community_id
        and g.active = true
        and g.deleted = false
        and e.canceled = false
        and e.deleted = false
        and e.published = true
    );
$$ language sql;
