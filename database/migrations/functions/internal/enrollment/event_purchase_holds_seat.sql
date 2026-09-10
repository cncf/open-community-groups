-- Returns whether an event purchase status keeps its seat occupied: settled
-- purchases and purchases whose refund is still in flight. Pending holds are
-- excluded because they expire and must be checked against hold_expires_at.
create or replace function event_purchase_holds_seat(p_status text)
returns boolean as $$
    select p_status in (
        'completed',
        'refund-pending',
        'refund-recovery-pending',
        'refund-requested'
    );
$$ language sql immutable;
