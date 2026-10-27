-- Returns the amount currently charged for a ticket type: the amount of its
-- current price window, or null when no window is open.
create or replace function event_ticket_type_current_price(p_event_ticket_type_id uuid)
returns bigint as $$
    select cpw.amount_minor
    from event_ticket_type_current_price_window(p_event_ticket_type_id) cpw;
$$ language sql stable;
