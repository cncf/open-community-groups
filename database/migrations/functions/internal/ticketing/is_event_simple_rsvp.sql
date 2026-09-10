-- Returns whether an event exposes one currently free public ticket type.
create or replace function is_event_simple_rsvp(p_event_id uuid)
returns boolean as $$
    select count(*) = 1
        and bool_and(public_ticket.amount_minor = 0)
    from (
        select event_ticket_type_current_price(ett.event_ticket_type_id) as amount_minor
        from event_ticket_type ett
        where ett.event_id = p_event_id
        and ett.active = true
        and ett.availability = 'public'
    ) public_ticket
    where public_ticket.amount_minor is not null;
$$ language sql;
