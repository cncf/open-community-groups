-- Rejects waitlist rows that conflict with attendee or admission offer state.
create or replace function check_event_waitlist_attendee()
returns trigger as $$
begin
    -- Serialize writes for the same event-user pair across enrollment tables
    perform pg_advisory_xact_lock(hashtext(new.event_id::text), hashtext(new.user_id::text));

    -- Reject waitlist entries for users already attending
    if exists (
        select 1
        from event_attendee ea
        where ea.event_id = new.event_id
        and ea.user_id = new.user_id
    ) then
        raise exception 'user is already attending this event' using errcode = 'OCG01';
    end if;

    -- Reject waitlist entries for users holding an active offer
    if exists (
        select 1
        from admission_offer ao
        where ao.event_id = new.event_id
        and ao.user_id = new.user_id
        and ao.status in ('checkout_pending', 'pending')
    ) then
        raise exception 'user already has an active admission offer for this event' using errcode = 'OCG01';
    end if;

    -- Return the validated waitlist row
    return new;
end;
$$ language plpgsql;
