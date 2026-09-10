-- Requires every surviving event to keep at least one ticket type.
create or replace function check_event_has_ticket_type()
returns trigger as $$
declare
    v_event_id uuid;
    v_event_ids uuid[];
begin
    -- Resolve the event written directly
    if tg_table_name = 'event' then
        v_event_ids := array[new.event_id];

    -- Resolve the event that received a new ticket type
    elsif tg_op = 'INSERT' then
        v_event_ids := array[new.event_id];

    -- Resolve the event that lost a ticket type
    elsif tg_op = 'DELETE' then
        v_event_ids := array[old.event_id];

    -- Resolve both sides of a ticket type move
    else
        v_event_ids := array[old.event_id, new.event_id];
    end if;

    -- Validate the settled ticket inventory for each surviving event
    foreach v_event_id in array v_event_ids
    loop
        -- Reject events left without any ticket type
        if exists (
            select 1
            from event e
            where e.event_id = v_event_id
        )
        and not exists (
            select 1
            from event_ticket_type ett
            where ett.event_id = v_event_id
        ) then
            raise exception 'events require at least one ticket type' using errcode = 'OCG01';
        end if;
    end loop;

    -- Constraint triggers ignore the returned row
    return null;
end;
$$ language plpgsql;
