-- Checks whether an event appears in public listings and counts: its page is
-- publicly visible and it is neither canceled nor a test event. Community scope
-- stays with the caller. Marked parallel safe so parallel count queries keep
-- their parallel plans, because the planner checks parallel safety before
-- inlining.
create or replace function is_event_listed(p_event event, p_group "group")
returns boolean as $$
    select is_event_public(p_event, p_group)
        and p_event.canceled = false
        and p_event.test_event = false;
$$ language sql immutable parallel safe;
