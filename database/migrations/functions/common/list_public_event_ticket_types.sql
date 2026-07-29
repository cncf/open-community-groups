-- Returns normalized public event ticket types as JSON.
create or replace function list_public_event_ticket_types(p_event_id uuid)
returns jsonb as $$
    select nullif(
        coalesce(
            jsonb_agg(ticket_type order by position),
            '[]'::jsonb
        ),
        '[]'::jsonb
    )
    from jsonb_array_elements(
        coalesce(list_event_ticket_types(p_event_id), '[]'::jsonb)
    ) with ordinality as ticket_types(ticket_type, position)
    where ticket_type->>'availability' = 'public';
$$ language sql;
