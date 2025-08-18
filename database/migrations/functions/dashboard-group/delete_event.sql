-- delete_event performs a soft delete on an event by setting deleted=true and deleted_at.
create or replace function delete_event(
    p_group_id uuid,
    p_event_id uuid
)
returns void as $$
begin
    update event set
        deleted = true,
        deleted_at = current_timestamp,
        published = false
    where event_id = p_event_id
    and group_id = p_group_id
    and deleted = false;

    if not found then
        raise exception 'event not found';
    end if;
end;
$$ language plpgsql;