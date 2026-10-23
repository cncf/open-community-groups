-- Returns some stats for the site home page.
-- Uses PL/pgSQL because PostgreSQL runs the final statement of a SQL-language
-- function with a row limit, which disables parallel plans for these counts.
create or replace function get_site_home_stats()
returns json as $$
begin
    -- Count listed events, their attendees, public groups and group members
    return (
        select json_build_object(
            -- Count listed events
            'events', (
                select count(*)
                from event e
                join "group" g using (group_id)
                join community c on c.community_id = g.community_id
                where c.active = true
                and is_event_listed(e, g)
            ),
            -- Count confirmed attendees across listed events
            'events_attendees', (
                select count(*)
                from event_attendee ea
                join event e using (event_id)
                join "group" g using (group_id)
                join community c on c.community_id = g.community_id
                where c.active = true
                and ea.status = 'confirmed'
                and is_event_listed(e, g)
            ),
            -- Count public groups
            'groups', (
                select count(*)
                from "group" g
                join community c on c.community_id = g.community_id
                where c.active = true
                and is_group_public(g)
            ),
            -- Count members across public groups
            'groups_members', (
                select count(*)
                from group_member gm
                join "group" g using (group_id)
                join community c on c.community_id = g.community_id
                where c.active = true
                and is_group_public(g)
            )
        )
    );
end;
$$ language plpgsql;
