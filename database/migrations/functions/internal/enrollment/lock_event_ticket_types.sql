-- Locks every ticket tier of an event in stable identifier order. Callers
-- lock the event row first, which serializes every enrollment writer of the
-- event; within it, this is the tier step of the preferred enrollment lock
-- order (ticket tiers, event-user locks, enrollment rows).
create or replace function lock_event_ticket_types(p_event_id uuid)
returns void as $$
begin
    -- Lock the event's ticket tiers in stable identifier order
    perform 1
    from event_ticket_type ett
    where ett.event_id = p_event_id
    order by ett.event_ticket_type_id
    for update of ett;
end;
$$ language plpgsql;
