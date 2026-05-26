-- Releases checkout-created pending attendee answers when no active purchase remains.
create or replace function release_event_checkout_attendee_hold(
    p_event_id uuid,
    p_user_id uuid
)
returns void as $$
    delete from event_attendee ea
    where ea.event_id = p_event_id
    and ea.user_id = p_user_id
    and ea.status = 'registration-questions-pending'
    and ea.manually_invited = false
    and exists (
        select 1
        from event_ticket_type ett
        where ett.event_id = ea.event_id
    )
    and not exists (
        select 1
        from event_purchase ep
        where ep.event_id = ea.event_id
        and ep.user_id = ea.user_id
        and (
            ep.status in ('completed', 'refund-requested')
            or (
                ep.status = 'pending'
                and ep.hold_expires_at > current_timestamp
            )
        )
    );
$$ language sql;
