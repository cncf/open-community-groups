-- Returns seat and discount code usage counts for a ticketed event.
create or replace function stats_event_tickets(p_event event)
returns json as $$
with seat_purchases as (
    select
        ep.event_discount_code_id,
        ep.event_ticket_type_id
    from event_purchase ep
    where ep.event_id = p_event.event_id
    and event_purchase_holds_seat(ep.status)
),
ticket_types as (
    select
        ett.active,
        get_event_ticket_type_allocated_seat_count(
            p_event.event_id,
            ett.event_ticket_type_id
        )::bigint as allocated,
        ett.event_ticket_type_id,
        ett."order",
        ett.seats_total,
        (
            select count(*)::bigint
            from seat_purchases sp
            where sp.event_ticket_type_id = ett.event_ticket_type_id
        ) as sold,
        ett.title
    from event_ticket_type ett
    where ett.event_id = p_event.event_id
)
select json_build_object(
    'discount_codes', coalesce((
        select json_agg(
            json_build_object(
                'active', edc.active,
                'code', edc.code,
                'event_discount_code_id', edc.event_discount_code_id,
                'redemptions', (
                    select count(*)::bigint
                    from seat_purchases sp
                    where sp.event_discount_code_id = edc.event_discount_code_id
                ),
                'title', edc.title,

                'available', edc.available,
                'total_available', edc.total_available
            )
            order by edc.code, edc.event_discount_code_id
        )
        from event_discount_code edc
        where edc.event_id = p_event.event_id
    ), '[]'::json),
    'ticket_types', coalesce((
        select json_agg(
            json_build_object(
                'active', tt.active,
                'allocated', tt.allocated,
                'event_ticket_type_id', tt.event_ticket_type_id,
                'order', tt."order",
                'remaining', greatest(tt.seats_total - tt.allocated, 0),
                'seats_total', tt.seats_total,
                'sold', tt.sold,
                'title', tt.title
            )
            order by tt."order", tt.title, tt.event_ticket_type_id
        )
        from ticket_types tt
    ), '[]'::json)
);
$$ language sql stable;
