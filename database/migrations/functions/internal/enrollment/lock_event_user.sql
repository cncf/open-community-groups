-- Takes the advisory lock that serializes one user's enrollment in an event
-- across event_attendee, event_waitlist, event_purchase and admission_offer.
-- The enrollment triggers take it before validating conflicting writes.
-- Every enrollment writer holds the event row lock first, which serializes
-- all enrollment changes of the event; after it, mutations prefer tier locks,
-- then this lock, then enrollment row locks. The triggers, refund approval
-- and the other-user locks reconcile takes for leave_event and
-- cancel_event_attendee_attendance take it after enrollment row locks, which
-- is safe only under the event lock. A caller without the event lock must not
-- hold enrollment row locks when it takes this lock.
create or replace function lock_event_user(
    p_event_id uuid,
    p_user_id uuid
)
returns void as $$
begin
    -- Serialize the event-user enrollment boundary for this transaction
    perform pg_advisory_xact_lock(hashtext(p_event_id::text), hashtext(p_user_id::text));
end;
$$ language plpgsql;
