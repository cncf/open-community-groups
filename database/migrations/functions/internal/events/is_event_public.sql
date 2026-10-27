-- Checks whether an event page is publicly visible: the event is published and
-- not deleted, and its group is publicly visible. Marked parallel safe so
-- parallel queries calling it keep their parallel plans.
create or replace function is_event_public(p_event event, p_group "group")
returns boolean as $$
    select p_event.published = true
        and p_event.deleted = false
        and is_group_public(p_group);
$$ language sql immutable parallel safe;
