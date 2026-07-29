-- Returns whether an event exposes one currently free public ticket type.
create or replace function is_event_simple_rsvp(p_event_id uuid)
returns boolean as $$
    select count(*) = 1
        and bool_and(public_ticket.amount_minor = 0)
    from (
        select (
            select etpw.amount_minor
            from event_ticket_price_window etpw
            where etpw.event_ticket_type_id = ett.event_ticket_type_id
            and (etpw.starts_at is null or etpw.starts_at <= current_timestamp)
            and (etpw.ends_at is null or etpw.ends_at >= current_timestamp)
            order by
                etpw.starts_at desc nulls last,
                etpw.event_ticket_price_window_id
            limit 1
        ) as amount_minor
        from event_ticket_type ett
        where ett.event_id = p_event_id
        and ett.active = true
        and ett.availability = 'public'
    ) public_ticket
    where public_ticket.amount_minor is not null;
$$ language sql;
