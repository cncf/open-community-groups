-- Rejects active admission offers that conflict with other enrollment state.
create or replace function check_admission_offer_enrollment_state()
returns trigger as $$
declare
    v_conflict text;
begin
    -- Ignore terminal offers that do not reserve capacity
    if not admission_offer_is_active(new.status) then
        return new;
    end if;

    -- Serialize writes for the same event-user enrollment boundary
    perform pg_advisory_xact_lock(hashtext(new.event_id::text), hashtext(new.user_id::text));

    -- Resolve the enrollment the user already holds, ignoring the purchase linked to this offer
    v_conflict := event_user_enrollment_conflict(new.event_id, new.user_id, new.admission_offer_id);

    -- Reject offers for users with active attendance
    if v_conflict = 'attendance' then
        raise exception 'user already has active attendance for this event' using errcode = 'OCG01';

    -- Reject offers for users waiting for a seat
    elsif v_conflict = 'waitlist' then
        raise exception 'user is already on the waiting list for this event' using errcode = 'OCG01';

    -- Reject offers for users with an open invitation request
    elsif v_conflict = 'request' then
        raise exception 'user already has a pending invitation request for this event' using errcode = 'OCG01';

    -- Reject offers for users holding a purchase not linked to this offer
    elsif v_conflict = 'purchase' then
        raise exception 'user already has an active purchase for this event' using errcode = 'OCG01';
    end if;

    -- Return the validated offer row
    return new;
end;
$$ language plpgsql;
