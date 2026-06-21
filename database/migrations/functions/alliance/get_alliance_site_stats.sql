-- Returns some stats for the alliance site page.
create or replace function get_alliance_site_stats(p_alliance_id uuid)
returns json as $$
    select json_build_object(
        -- Count active groups in the alliance
        'groups', (
            select count(*)
            from "group"
            where alliance_id = p_alliance_id
            and active = true
            and deleted = false
        ),
        -- Count members across active alliance groups
        'groups_members', (
            select count(*)
            from group_member gm
            join "group" g using (group_id)
            where alliance_id = p_alliance_id
            and g.active = true
            and g.deleted = false
        ),
        -- Count active published alliance events
        'events', (
            select count(*)
            from event e
            join "group" g using (group_id)
            where g.alliance_id = p_alliance_id
            and g.active = true
            and g.deleted = false
            and e.canceled = false
            and e.deleted = false
            and e.published = true
            and e.test_event = false
        ),
        -- Count attendees across active published alliance events
        'events_attendees', (
            select count(*)
            from event_attendee ea
            join event e using (event_id)
            join "group" g using (group_id)
            where alliance_id = p_alliance_id
            and ea.status = 'confirmed'
            and g.active = true
            and g.deleted = false
            and e.canceled = false
            and e.deleted = false
            and e.published = true
            and e.test_event = false
        )
    );
$$ language sql;
