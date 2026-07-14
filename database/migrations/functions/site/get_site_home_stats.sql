-- Returns some stats for the site home page.
create or replace function get_site_home_stats()
returns json as $$
    select json_build_object(
        -- Count published events
        'events', (
            select count(*)
            from event e
            join "group" g using (group_id)
            join community c on c.community_id = g.community_id
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
            join community c on c.community_id = g.community_id
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
            join community c on c.community_id = g.community_id
            where c.active = true
            and g.active = true
            and g.deleted = false
        ),
        -- Count groups members
        'groups_members', (
            select count(*)
            from group_member gm
            join "group" g using (group_id)
            join community c on c.community_id = g.community_id
            where c.active = true
            and g.active = true
            and g.deleted = false
        )
    );
$$ language sql;
