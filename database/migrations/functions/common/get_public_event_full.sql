-- Returns public full information about an event.
create or replace function get_public_event_full(
    p_community_id uuid,
    p_group_id uuid,
    p_event_id uuid
)
returns json as $$
    with
    -- Load attendee-facing ticket types once for all public projections
    public_ticket_projection as (
        select list_public_event_ticket_types(p_event_id) as ticket_types
    ),
    -- Sum inventory from ticket types currently visible to attendees
    public_ticket_inventory as (
        select
            sum((ticket_type->>'seats_total')::int)::int as capacity,
            sum((ticket_type->>'remaining_seats')::int)::int as remaining_capacity
        from public_ticket_projection ptp
        cross join lateral jsonb_array_elements(
            coalesce(ptp.ticket_types, '[]'::jsonb)
        ) as public_ticket_types(ticket_type)
        where (ticket_type->>'active')::boolean
        and ticket_type ? 'current_price'
    )
    -- Replace organizer inventory with attendee-facing ticket totals
    select (
        (
            get_event_full(p_community_id, p_group_id, p_event_id)::jsonb
            - 'capacity'
            - 'remaining_capacity'
            - 'ticket_types'
        )
        || jsonb_strip_nulls(
            jsonb_build_object(
                'capacity', pti.capacity,
                'ticket_types', ptp.ticket_types,

                'remaining_capacity', pti.remaining_capacity
            )
        )
    )::json
    from public_ticket_inventory pti
    cross join public_ticket_projection ptp;
$$ language sql;
