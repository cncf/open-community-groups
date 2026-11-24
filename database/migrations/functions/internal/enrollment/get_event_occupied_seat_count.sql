-- Returns the number of reservations that currently occupy event capacity.
-- Uses PL/pgSQL with `force_generic_plan` so each connection caches its plan:
-- event lists call it once per event, and a SQL-language body is planned
-- again on each call (PostgreSQL 17 and earlier). The setting also keeps a
-- caller's `force_custom_plan` from planning it on every call.
create or replace function get_event_occupied_seat_count(p_event_id uuid)
returns int as $$
begin
    -- Count the seats held by attendees, offers and purchases
    return (
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
            and admission_offer_reserves_seat(ao.status, ao.expires_at)

            union

            -- Count paid reservations even when no attendee row remains
            select ep.user_id
            from event_purchase ep
            where ep.event_id = p_event_id
            and event_purchase_reserves_seat(ep.status, ep.hold_expires_at)
        ) occupied_users
    );
end;
$$ language plpgsql stable set plan_cache_mode = force_generic_plan;
