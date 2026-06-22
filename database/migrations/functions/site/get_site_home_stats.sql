-- Returns some stats for the site home page.
create or replace function get_site_home_stats()
returns json as $$
    select json_build_object(
        -- Count active alliances
        'alliances', (
            select count(*)
            from alliance
            where active = true
        ),
        -- Count published events
        'events', (
            select count(*)
            from event e
            join "group" g using (group_id)
            join alliance c on c.alliance_id = g.alliance_id
            where c.active = true
            and g.active = true
            and g.deleted = false
            and e.canceled = false
            and e.deleted = false
            and e.published = true
            and e.test_event = false
        ),
        -- Count attendees across published events
        'events_attendees', (
            select count(*)
            from event_attendee ea
            join event e using (event_id)
            join "group" g using (group_id)
            join alliance c on c.alliance_id = g.alliance_id
            where c.active = true
            and g.active = true
            and ea.status = 'confirmed'
            and g.deleted = false
            and e.canceled = false
            and e.deleted = false
            and e.published = true
            and e.test_event = false
        ),
        -- Count groups
        'groups', (
            select count(*)
            from "group" g
            join alliance c on c.alliance_id = g.alliance_id
            where c.active = true
            and g.active = true
            and g.deleted = false
        ),
        -- Count groups members
        'groups_members', (
            select count(*)
            from group_member gm
            join "group" g using (group_id)
            join alliance c on c.alliance_id = g.alliance_id
            where c.active = true
            and g.active = true
            and g.deleted = false
        )
    );
$$ language sql;
