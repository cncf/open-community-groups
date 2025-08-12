-- delete_event performs a soft delete on an event by setting deleted=true and deleted_at.
create or replace function delete_event(p_event_id uuid)
returns void as $$
    update event set
        deleted = true,
        deleted_at = current_timestamp,
        published = false
    where event_id = p_event_id
    and deleted = false;
$$ language sql;