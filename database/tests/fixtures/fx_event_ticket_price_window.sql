-- Inserts a baseline free event ticket price window row with placeholder plumbing.
create or replace function fx_event_ticket_price_window(
    p_event_ticket_price_window_id uuid,
    p_event_ticket_type_id uuid,
    p_overrides jsonb default '{}'::jsonb
)
returns void as $$
begin
    perform fx_insert_row('event_ticket_price_window', jsonb_build_object(
        'amount_minor', 0,
        'event_ticket_price_window_id', p_event_ticket_price_window_id,
        'event_ticket_type_id', p_event_ticket_type_id
    ) || p_overrides);
end;
$$ language plpgsql;
