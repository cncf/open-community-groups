-- Checks whether the page of an event linked from the inbox is publicly available.
create or replace function is_inbox_event_public(p_event event, p_group "group")
returns boolean as $$
    select p_event.published = true
        and p_event.deleted = false
        and p_group.active = true
        and p_group.deleted = false;
$$ language sql immutable;
