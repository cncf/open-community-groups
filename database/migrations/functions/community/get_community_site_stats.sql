-- Returns some stats for the community site page.
create or replace function get_community_site_stats(p_community_id uuid)
returns json as $$
    select json_build_object(
        -- Count active groups in the community
        'groups', (
            select count(*)
            from "group"
            where community_id = p_community_id
            and active = true
            and deleted = false
        ),
        -- Count members across active community groups
        'groups_members', (
            select count(*)
            from group_member gm
            join "group" g using (group_id)
            where community_id = p_community_id
            and g.active = true
            and g.deleted = false
        ),
        -- Count active published community events
        'events', (
            select count(*)
            from event e
            join "group" g using (group_id)
            where g.community_id = p_community_id
            and g.active = true
            and g.deleted = false
            and e.canceled = false
            and e.deleted = false
            and e.published = true
        ),
        -- Count attendees across active published community events
        'events_attendees', (
            select count(*)
            from event_attendee ea
            join event e using (event_id)
            join "group" g using (group_id)
            where community_id = p_community_id
            and g.active = true
            and g.deleted = false
            and e.canceled = false
            and e.deleted = false
            and e.published = true
        )
    );
$$ language sql;
