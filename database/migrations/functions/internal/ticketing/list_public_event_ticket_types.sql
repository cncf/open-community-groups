-- Returns normalized public event ticket types as JSON.
create or replace function list_public_event_ticket_types(p_event_id uuid)
returns jsonb as $$
    select event_ticket_types_public_json(list_event_ticket_types(p_event_id));
$$ language sql stable;
