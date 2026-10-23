-- Returns the price window currently open for a ticket type: the one that
-- started most recently, or no row when no window is open.
create or replace function event_ticket_type_current_price_window(p_event_ticket_type_id uuid)
returns setof event_ticket_price_window as $$
    select etpw.*
    from event_ticket_price_window etpw
    where etpw.event_ticket_type_id = p_event_ticket_type_id
    and (etpw.starts_at is null or etpw.starts_at <= current_timestamp)
    and (etpw.ends_at is null or etpw.ends_at >= current_timestamp)
    order by
        etpw.starts_at desc nulls last,
        etpw.event_ticket_price_window_id
    limit 1;
$$ language sql stable rows 1;
