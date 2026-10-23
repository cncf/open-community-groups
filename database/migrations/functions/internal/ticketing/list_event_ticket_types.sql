-- list_event_ticket_types returns normalized event ticket types as JSON.
create or replace function list_event_ticket_types(p_event_id uuid)
returns jsonb as $$
    with
    -- Resolve allocated inventory once per tier through the canonical capacity
    -- helper; materialized so each reference reuses the count
    ticket_allocation as materialized (
        select
            ett.event_ticket_type_id,
            get_event_ticket_type_allocated_seat_count(
                p_event_id,
                ett.event_ticket_type_id
            ) as allocated_seat_count
        from event_ticket_type ett
        where ett.event_id = p_event_id
    )
    -- Build the final normalized ticket type payload
    select jsonb_agg(
        jsonb_strip_nulls(
            jsonb_build_object(
                'active', ett.active,
                'availability', ett.availability,
                'current_price', case
                    -- Project the price window open right now
                    when cpw.event_ticket_price_window_id is not null then jsonb_strip_nulls(
                        jsonb_build_object(
                            'amount_minor', cpw.amount_minor,
                            'ends_at', cpw.ends_at,
                            'starts_at', cpw.starts_at
                        )
                    )
                end,
                'description', ett.description,
                'event_ticket_type_id', ett.event_ticket_type_id,
                'order', ett."order",
                'price_windows', (
                    select coalesce(
                        jsonb_agg(
                            jsonb_strip_nulls(
                                jsonb_build_object(
                                    'amount_minor', etpw.amount_minor,
                                    'ends_at', etpw.ends_at,
                                    'event_ticket_price_window_id', etpw.event_ticket_price_window_id,
                                    'starts_at', etpw.starts_at
                                )
                            )
                            order by
                                etpw.starts_at asc nulls first,
                                etpw.ends_at asc nulls last,
                                etpw.event_ticket_price_window_id asc
                        ),
                        '[]'::jsonb
                    )
                    from event_ticket_price_window etpw
                    where etpw.event_ticket_type_id = ett.event_ticket_type_id
                ),
                'remaining_seats', case
                    -- Unlimited tiers have no remaining seat count
                    when ett.seats_total is null then null
                    -- Limited tiers never report negative remaining seats
                    else greatest(
                        ett.seats_total - ta.allocated_seat_count,
                        0
                    )
                end,
                'seats_total', ett.seats_total,
                'sold_out', case
                    -- Unlimited tiers never sell out
                    when ett.seats_total is null then false
                    -- Limited tiers sell out once allocations reach capacity
                    else ta.allocated_seat_count >= ett.seats_total
                end,
                'title', ett.title
            )
        )
        order by ett."order" asc, ett.title asc, ett.event_ticket_type_id asc
    )
    from event_ticket_type ett
    join ticket_allocation ta on ta.event_ticket_type_id = ett.event_ticket_type_id
    left join lateral event_ticket_type_current_price_window(ett.event_ticket_type_id) cpw on true
    where ett.event_id = p_event_id;
$$ language sql stable;
