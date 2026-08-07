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
            and ao.status in ('checkout_pending', 'pending')
            and ao.expires_at > current_timestamp
        )
        +
        (
            select count(distinct coalesce(ep.admission_offer_id, ep.event_purchase_id))
            from event_purchase ep
            where ep.event_id = p_event_id
            and ep.event_ticket_type_id = p_event_ticket_type_id
            and (
                ep.status in (
                    'completed',
                    'refund-pending',
                    'refund-recovery-pending',
                    'refund-requested'
                )
                or (
                    ep.status = 'pending'
                    and ep.hold_expires_at > current_timestamp
                )
            )
            and not exists (
                select 1
                from admission_offer ao
                where ao.admission_offer_id = ep.admission_offer_id
                and ao.status in ('checkout_pending', 'pending')
                and ao.expires_at > current_timestamp
            )
        )
    )::int;
$$ language sql;
