-- Returns the number of attendee rows that currently occupy event capacity.
create or replace function get_event_occupied_seat_count(p_event_id uuid)
returns int as $$
    select count(*)::int
    from event_attendee ea
    where ea.event_id = p_event_id
    and (
        ea.status = 'confirmed'
        or (
            ea.status = 'registration-questions-pending'
            and (
                -- Count pending seats that are not checkout-created holds
                ea.manually_invited = true
                or not exists (
                    select 1
                    from event_ticket_type ett
                    where ett.event_id = ea.event_id
                )
                -- Count checkout-created pending seats only while their hold is active
                or exists (
                    select 1
                    from event_purchase ep
                    where ep.event_id = ea.event_id
                    and ep.user_id = ea.user_id
                    and ep.status = 'pending'
                    and ep.hold_expires_at > current_timestamp
                )
            )
        )
    );
$$ language sql;
