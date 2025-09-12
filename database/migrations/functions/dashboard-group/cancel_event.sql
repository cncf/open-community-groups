-- cancel_event marks an event as canceled and clears publication metadata.
create or replace function cancel_event(
    p_group_id uuid,
    p_event_id uuid
)
returns void as $$
begin
    update event set
        canceled = true,
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

