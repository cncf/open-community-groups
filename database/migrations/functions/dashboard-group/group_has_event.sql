-- Returns whether an event exists, is not deleted and belongs to the group.
create or replace function group_has_event(
    p_group_id uuid,
    p_event_id uuid
)
returns boolean as $$
    select exists (
        select 1
        from event e
        where e.event_id = p_event_id
        and e.group_id = p_group_id
        and e.deleted = false
    );
$$ language sql stable;
