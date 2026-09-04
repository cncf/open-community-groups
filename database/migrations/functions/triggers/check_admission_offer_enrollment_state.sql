-- Rejects active admission offers that conflict with other enrollment state.
create or replace function check_admission_offer_enrollment_state()
returns trigger as $$
begin
    -- Ignore terminal offers that do not reserve capacity
    if new.status not in ('checkout_pending', 'pending') then
        return new;
    end if;

    -- Serialize writes for the same event-user enrollment boundary
    perform pg_advisory_xact_lock(hashtext(new.event_id::text), hashtext(new.user_id::text));

    -- Reject offers for users with active attendance
    if exists (
        select 1
        from event_attendee ea
        where ea.event_id = new.event_id
        and ea.user_id = new.user_id
        and ea.status in ('confirmed', 'invitation-pending', 'registration-questions-pending')
    ) then
        raise exception 'user already has active attendance for this event' using errcode = 'OCG01';
    end if;

    -- Reject offers for users waiting for a seat
    if exists (
        select 1
        from event_waitlist ew
        where ew.event_id = new.event_id
        and ew.user_id = new.user_id
    ) then
        raise exception 'user is already on the waiting list for this event' using errcode = 'OCG01';
    end if;

    -- Reject offers for users with an open invitation request
    if exists (
        select 1
        from event_invitation_request eir
        where eir.event_id = new.event_id
        and eir.user_id = new.user_id
        and eir.status = 'pending'
    ) then
        raise exception 'user already has a pending invitation request for this event' using errcode = 'OCG01';
    end if;

    -- Reject offers for users holding a purchase not linked to this offer
    if exists (
        select 1
        from event_purchase ep
        where ep.event_id = new.event_id
        and ep.user_id = new.user_id
        and ep.status in (
            'completed',
            'pending',
            'refund-pending',
            'refund-recovery-pending',
            'refund-requested'
        )
        and ep.admission_offer_id is distinct from new.admission_offer_id
    ) then
        raise exception 'user already has an active purchase for this event' using errcode = 'OCG01';
    end if;

    -- Return the validated offer row
    return new;
end;
$$ language plpgsql;
