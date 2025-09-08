-- archive_event sets published=false and clears publication metadata for an event.
create or replace function archive_event(
    p_group_id uuid,
    p_event_id uuid
)
returns void as $$
begin
    update event set
        published = false,
        published_at = null,
        published_by = null
    where event_id = p_event_id
    and group_id = p_group_id
    and deleted = false;

    if not found then
        raise exception 'event not found';
    end if;
end;
$$ language plpgsql;

