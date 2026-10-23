-- Keeps the attendee-visible public tiers of a normalized ticket type list
-- (list_event_ticket_types output) in their original order; null when none remain.
create or replace function event_ticket_types_public_json(p_ticket_types jsonb)
returns jsonb as $$
    select jsonb_agg(t.ticket_type order by t.position)
    from jsonb_array_elements(coalesce(p_ticket_types, '[]'::jsonb))
        with ordinality as t(ticket_type, position)
    where t.ticket_type->>'availability' = 'public';
$$ language sql immutable;
