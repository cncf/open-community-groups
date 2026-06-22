-- Returns a list of all active alliances with at least one group and one event.
create or replace function list_alliances()
returns json as $$
    select coalesce(json_agg(
        get_alliance_summary(alliance_id) order by display_name
    ), '[]')
    from alliance c
    where c.active = true
    and exists (
        select 1
        from "group" g
        where g.alliance_id = c.alliance_id
        and g.active = true
        and g.deleted = false
    )
    and exists (
        select 1
        from event e
        join "group" g using (group_id)
        where g.alliance_id = c.alliance_id
        and g.active = true
        and g.deleted = false
        and e.canceled = false
        and e.deleted = false
        and e.published = true
        and e.test_event = false
    );
$$ language sql;
