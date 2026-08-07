-- list_event_ticket_types returns normalized event ticket types as JSON.
create or replace function list_event_ticket_types(p_event_id uuid)
returns jsonb as $$
    with
    -- Select the current price window for each ticket type
    current_price as (
        select distinct on (ett.event_ticket_type_id)
            ett.event_ticket_type_id,
            jsonb_strip_nulls(
                jsonb_build_object(
                    'amount_minor', etpw.amount_minor,
                    'ends_at', etpw.ends_at,
                    'starts_at', etpw.starts_at
                )
            ) as current_price
        from event_ticket_type ett
        join event_ticket_price_window etpw
            on etpw.event_ticket_type_id = ett.event_ticket_type_id
        where ett.event_id = p_event_id
        and (
            etpw.starts_at is null
            or etpw.starts_at <= current_timestamp
        )
        and (
            etpw.ends_at is null
            or etpw.ends_at >= current_timestamp
        )
        order by
            ett.event_ticket_type_id,
            etpw.starts_at desc nulls last,
            etpw.event_ticket_price_window_id asc
    ),
    -- Resolve allocated inventory through the canonical capacity helper
    ticket_allocation as (
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
    select nullif(
        coalesce(
            jsonb_agg(
                jsonb_strip_nulls(
                    jsonb_build_object(
                        'active', ett.active,
                        'availability', ett.availability,
                        'current_price', cp.current_price,
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
                            when ett.seats_total is null then null
                            else greatest(
                                ett.seats_total - ta.allocated_seat_count,
                                0
                            )
                        end,
                        'seats_total', ett.seats_total,
                        'sold_out', case
                            when ett.seats_total is null then false
                            else ta.allocated_seat_count >= ett.seats_total
                        end,
                        'title', ett.title
                    )
                )
                order by ett."order" asc, ett.title asc, ett.event_ticket_type_id asc
            ),
            '[]'::jsonb
        ),
        '[]'::jsonb
    )
    from event_ticket_type ett
    left join current_price cp on cp.event_ticket_type_id = ett.event_ticket_type_id
    join ticket_allocation ta on ta.event_ticket_type_id = ett.event_ticket_type_id
    where ett.event_id = p_event_id;
$$ language sql;
