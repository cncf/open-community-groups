-- Rejects co-host rows that point back at the owning event group.
create or replace function check_event_cohost_group()
returns trigger as $$
declare
    v_event_group_id uuid;
begin
    -- Resolve the group that owns the event
    select group_id
    into v_event_group_id
    from event
    where event_id = new.event_id;

    -- Reject self co-hosting
    if new.group_id = v_event_group_id then
        raise exception 'event group cannot co-host its own event';
    end if;

    -- Return the validated co-host row
    return new;
end;
$$ language plpgsql;
