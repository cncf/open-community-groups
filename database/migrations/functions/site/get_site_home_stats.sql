-- Returns some stats for the site home page.
create or replace function get_site_home_stats()
returns json as $$
    select json_build_object(
        -- Count active communities
        'communities', (
            select count(*)
            from community
            where active = true
        ),
        -- Count active published events
        'events', (
            select count(*)
            from event e
            join "group" g using (group_id)
            where g.active = true
            and g.deleted = false
            and e.canceled = false
            and e.deleted = false
            and e.published = true
        ),
        -- Count attendees across active published events
        'events_attendees', (
            select count(*)
            from event_attendee ea
            join event e using (event_id)
            join "group" g using (group_id)
            where g.active = true
            and g.deleted = false
            and e.canceled = false
            and e.deleted = false
            and e.published = true
        ),
        -- Count active groups
        'groups', (
            select count(*)
            from "group"
            where active = true
            and deleted = false
        ),
        -- Count members in active groups
        'groups_members', (
            select count(*)
            from group_member gm
            join "group" g using (group_id)
            where g.active = true
            and g.deleted = false
        )
    );
$$ language sql;
