-- Reports the enrollment a user already holds for an event that excludes a new
-- admission offer, strongest first: attendance (active attendee row), waitlist
-- (queue entry), request (pending invitation request) or purchase (seat-holding
-- or pending purchase not linked to p_admission_offer_id; every purchase counts
-- when it is null). Returns null when the user holds no such enrollment.
create or replace function event_user_enrollment_conflict(
    p_event_id uuid,
    p_user_id uuid,
    p_admission_offer_id uuid
)
returns text as $$
    select case
        -- Active attendance already holds or awaits the seat
        when exists (
            select 1
            from event_attendee ea
            where ea.event_id = p_event_id
            and ea.status in ('confirmed', 'invitation-pending', 'registration-questions-pending')
            and ea.user_id = p_user_id
        ) then 'attendance'
        -- Queued users wait for a waitlist offer instead
        when exists (
            select 1
            from event_waitlist ew
            where ew.event_id = p_event_id
            and ew.user_id = p_user_id
        ) then 'waitlist'
        -- Open requests must be reviewed before any offer
        when exists (
            select 1
            from event_invitation_request eir
            where eir.event_id = p_event_id
            and eir.status = 'pending'
            and eir.user_id = p_user_id
        ) then 'request'
        -- Purchases hold the seat or are still checking out
        when exists (
            select 1
            from event_purchase ep
            where ep.event_id = p_event_id
            and (event_purchase_holds_seat(ep.status) or ep.status = 'pending')
            and (
                p_admission_offer_id is null
                or ep.admission_offer_id is distinct from p_admission_offer_id
            )
            and ep.user_id = p_user_id
        ) then 'purchase'
        -- No enrollment excludes a new offer
        else null
    end;
$$ language sql stable;
