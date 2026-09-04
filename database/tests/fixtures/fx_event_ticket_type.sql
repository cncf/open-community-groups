-- Inserts a baseline event ticket type row with placeholder plumbing.
create or replace function fx_event_ticket_type(
    p_event_ticket_type_id uuid,
    p_event_id uuid,
    p_overrides jsonb default '{}'::jsonb
)
returns void as $$
begin
    perform fx_insert_row('event_ticket_type', jsonb_build_object(
        'event_id', p_event_id,
        'event_ticket_type_id', p_event_ticket_type_id,
        'order', 1,
        'seats_total', 10,
        'title', 'Fixture Ticket Type'
    ) || p_overrides);
end;
$$ language plpgsql;
