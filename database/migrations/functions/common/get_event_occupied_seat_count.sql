-- Returns the number of reservations that currently occupy event capacity.
create or replace function get_event_occupied_seat_count(p_event_id uuid)
returns int as $$
    select count(*)::int
    from (
        -- Count confirmed attendees and checkout-owned questionnaire reservations
        select ea.user_id
        from event_attendee ea
        where ea.event_id = p_event_id
        and (
            ea.status = 'confirmed'
            or (
                ea.status = 'registration-questions-pending'
                and exists (
                    select 1
                    from event_purchase ep
                    where ep.event_id = ea.event_id
                    and ep.user_id = ea.user_id
                    and ep.status = 'pending'
                    and ep.hold_expires_at > current_timestamp
                )
            )
        )

        union

        -- Count unclaimed tier offers
        select ao.user_id
        from admission_offer ao
        where ao.event_id = p_event_id
        and ao.status in ('checkout_pending', 'pending')
        and ao.expires_at > current_timestamp

        union

        -- Count paid reservations even when no attendee row remains
        select ep.user_id
        from event_purchase ep
        where ep.event_id = p_event_id
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
    ) occupied_users;
$$ language sql;
