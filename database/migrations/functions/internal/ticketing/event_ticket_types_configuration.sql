-- Projects a ticket types payload (stored or submitted) onto the configuration
-- compared by event_ticketing_configuration_changed: read-model-only fields
-- are dropped, tier and price window order is preserved and window schedules
-- are normalized through normalize_ticketing_schedule. Comparison-only; never
-- written back or returned to callers.
create or replace function event_ticket_types_configuration(p_ticket_types jsonb)
returns jsonb as $$
    select coalesce(
        jsonb_agg(
            (ticket_type - 'current_price' - 'remaining_seats' - 'sold_out')
            || jsonb_build_object('price_windows', (
                select coalesce(
                    jsonb_agg(normalize_ticketing_schedule(price_window) order by ordinality),
                    '[]'::jsonb
                )
                from jsonb_array_elements(coalesce(ticket_type->'price_windows', '[]'::jsonb))
                    with ordinality as price_windows(price_window, ordinality)
            ))
            order by ordinality
        ),
        '[]'::jsonb
    )
    from jsonb_array_elements(coalesce(nullif(p_ticket_types, 'null'::jsonb), '[]'::jsonb))
        with ordinality as ticket_types(ticket_type, ordinality);
$$ language sql stable;
