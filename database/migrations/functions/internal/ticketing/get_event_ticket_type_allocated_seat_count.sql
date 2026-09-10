-- Returns the number of seats allocated for an event ticket type.
create or replace function get_event_ticket_type_allocated_seat_count(
    p_event_id uuid,
    p_event_ticket_type_id uuid
)
returns int as $$
    select (
        (
            select count(*)
            from admission_offer ao
            where ao.event_id = p_event_id
            and ao.event_ticket_type_id = p_event_ticket_type_id
            and admission_offer_is_active(ao.status)
            and ao.expires_at > current_timestamp
        )
        +
        (
            select count(distinct coalesce(ep.admission_offer_id, ep.event_purchase_id))
            from event_purchase ep
            where ep.event_id = p_event_id
            and ep.event_ticket_type_id = p_event_ticket_type_id
            and (
                event_purchase_holds_seat(ep.status)
                or (
                    ep.status = 'pending'
                    and ep.hold_expires_at > current_timestamp
                )
            )
            and not exists (
                select 1
                from admission_offer ao
                where ao.admission_offer_id = ep.admission_offer_id
                and admission_offer_is_active(ao.status)
                and ao.expires_at > current_timestamp
            )
        )
    )::int;
$$ language sql;
