-- Returns whether an event has any configured positive ticket price.
create or replace function is_event_paid_capable(p_event_id uuid)
returns boolean as $$
    select exists (
        select 1
        from event_ticket_price_window etpw
        join event_ticket_type ett
            on ett.event_ticket_type_id = etpw.event_ticket_type_id
        where ett.event_id = p_event_id
        and etpw.amount_minor > 0
    );
$$ language sql;
