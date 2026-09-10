-- Tests the purchase seat-holding status predicate.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should treat settled and refund-in-flight purchases as holding a seat
select is(
    array_agg(status order by status),
    array['completed', 'refund-pending', 'refund-recovery-pending', 'refund-requested'],
    'Should treat settled and refund-in-flight purchases as holding a seat'
)
from unnest(array[
    'completed', 'expired', 'pending', 'refund-pending',
    'refund-recovery-pending', 'refund-requested', 'refunded'
]) as status
where event_purchase_holds_seat(status);

-- Should treat pending, expired and refunded purchases as releasing the seat
select is(
    array_agg(status order by status),
    array['expired', 'pending', 'refunded'],
    'Should treat pending, expired and refunded purchases as releasing the seat'
)
from unnest(array[
    'completed', 'expired', 'pending', 'refund-pending',
    'refund-recovery-pending', 'refund-requested', 'refunded'
]) as status
where not event_purchase_holds_seat(status);

-- Should return null for a null status
select is(
    event_purchase_holds_seat(null),
    null::boolean,
    'Should return null for a null status'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
