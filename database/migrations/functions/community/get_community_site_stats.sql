-- Returns some stats for the community site page.
-- Uses PL/pgSQL because PostgreSQL runs the final statement of a SQL-language
-- function with a row limit, which disables parallel plans for these counts.
create or replace function get_community_site_stats(p_community_id uuid)
returns json as $$
begin
    -- Count the community groups, members, events and attendees
    return (
        select json_build_object(
            -- Count public groups in the community
            'groups', (
                select count(*)
                from "group" g
                where g.community_id = p_community_id
                and is_group_public(g)
            ),
            -- Count members across public community groups
            'groups_members', (
                select count(*)
                from group_member gm
                join "group" g using (group_id)
                where g.community_id = p_community_id
                and is_group_public(g)
            ),
            -- Count listed community events
            'events', (
                select count(*)
                from event e
                join "group" g using (group_id)
                where g.community_id = p_community_id
                and is_event_listed(e, g)
            ),
            -- Count confirmed attendees across listed community events
            'events_attendees', (
                select count(*)
                from event_attendee ea
                join event e using (event_id)
                join "group" g using (group_id)
                where g.community_id = p_community_id
                and ea.status = 'confirmed'
                and is_event_listed(e, g)
            )
        )
    );
end;
$$ language plpgsql;
