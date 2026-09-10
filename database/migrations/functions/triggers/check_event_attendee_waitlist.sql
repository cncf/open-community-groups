-- Rejects attendee rows that conflict with waitlist or admission offer state.
create or replace function check_event_attendee_waitlist()
returns trigger as $$
begin
    -- Serialize writes for the same event-user pair across enrollment tables
    perform pg_advisory_xact_lock(hashtext(new.event_id::text), hashtext(new.user_id::text));

    -- Reject attendees already waiting for a seat
    if exists (
        select 1
        from event_waitlist ew
        where ew.event_id = new.event_id
        and ew.user_id = new.user_id
    ) then
        raise exception 'user is already on the waiting list for this event' using errcode = 'OCG01';
    end if;

    -- Reject attendees holding an active offer, except the checkout claim itself
    if exists (
        select 1
        from admission_offer ao
        where ao.event_id = new.event_id
        and ao.user_id = new.user_id
        and admission_offer_is_active(ao.status)
        and not (
            new.status = 'registration-questions-pending'
            and ao.status = 'checkout_pending'
        )
    ) then
        raise exception 'user already has an active admission offer for this event' using errcode = 'OCG01';
    end if;

    -- Return the validated attendee row
    return new;
end;
$$ language plpgsql;
