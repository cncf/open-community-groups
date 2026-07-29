-- Returns whether a ticket configuration payload has any positive price.
create or replace function is_event_ticketing_payload_paid_capable(p_ticket_types jsonb)
returns boolean as $$
    select exists (
        select 1
        from jsonb_array_elements(coalesce(p_ticket_types, '[]'::jsonb))
            as ticket_types(ticket_type)
        cross join lateral jsonb_array_elements(
            coalesce(ticket_type->'price_windows', '[]'::jsonb)
        ) as price_windows(price_window)
        where (price_window->>'amount_minor')::bigint > 0
    );
$$ language sql;
