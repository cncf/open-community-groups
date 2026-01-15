-- Returns some stats for the site home page.
create or replace function get_site_home_stats()
returns json as $$
    select json_build_object(
        'communities', (
            select count(*)
            from community
            where active = true
        ),
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
        'groups', (
            select count(*)
            from "group"
            where active = true
            and deleted = false
        ),
        'groups_members', (
            select count(*)
            from group_member gm
            join "group" g using (group_id)
            where g.active = true
            and g.deleted = false
        )
    );
$$ language sql;
