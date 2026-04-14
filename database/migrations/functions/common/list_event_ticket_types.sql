-- list_event_ticket_types returns normalized event ticket types as JSON.
create or replace function list_event_ticket_types(p_event_id uuid)
returns jsonb as $$
    with
    -- Count attendees and open purchases per ticket type
    ticket_usage as (
        select
            ep.event_ticket_type_id,
            count(*)::int as purchase_count
        from event_purchase ep
        where ep.event_id = p_event_id
        and ep.status in ('completed', 'pending', 'refund-requested')
        and (
            ep.status <> 'pending'
            or ep.hold_expires_at > current_timestamp
        )
        group by ep.event_ticket_type_id
    ),
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
    )
    -- Build the final normalized ticket type payload
    select nullif(
        coalesce(
            jsonb_agg(
                jsonb_strip_nulls(
                    jsonb_build_object(
                        'active', ett.active,
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
                                ett.seats_total - coalesce(tu.purchase_count, 0),
                                0
                            )
                        end,
                        'seats_total', ett.seats_total,
                        'sold_out', case
                            when ett.seats_total is null then false
                            else coalesce(tu.purchase_count, 0) >= ett.seats_total
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
    left join ticket_usage tu on tu.event_ticket_type_id = ett.event_ticket_type_id
    where ett.event_id = p_event_id;
$$ language sql;
