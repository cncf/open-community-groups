-- Tests the purchase seat-reservation predicate.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should not reserve seats for expired and refunded purchases
select is(
    array_agg(status order by status),
    null::text[],
    'Should not reserve seats for expired and refunded purchases'
)
from unnest(array['expired', 'refunded']) as status
where event_purchase_reserves_seat(status, current_timestamp + interval '1 hour');

-- Should not reserve seats for pending purchases whose hold expired
select is(
    event_purchase_reserves_seat('pending', current_timestamp - interval '1 minute'),
    false,
    'Should not reserve seats for pending purchases whose hold expired'
);

-- Should not reserve seats for pending purchases whose hold expires now
select is(
    event_purchase_reserves_seat('pending', current_timestamp),
    false,
    'Should not reserve seats for pending purchases whose hold expires now'
);

-- Should reserve seats for pending purchases with a future hold
select is(
    event_purchase_reserves_seat('pending', current_timestamp + interval '1 minute'),
    true,
    'Should reserve seats for pending purchases with a future hold'
);

-- Should reserve seats for seat-holding purchases regardless of their hold
select is(
    array_agg(status order by status),
    array[
        'completed', 'completed', 'refund-pending', 'refund-pending',
        'refund-recovery-pending', 'refund-recovery-pending',
        'refund-requested', 'refund-requested'
    ],
    'Should reserve seats for seat-holding purchases regardless of their hold'
)
from unnest(array[
    'completed', 'expired', 'pending', 'refund-pending',
    'refund-recovery-pending', 'refund-requested', 'refunded'
]) as status
cross join unnest(array[
    current_timestamp - interval '1 hour',
    null::timestamptz
]) as hold_expires_at
where event_purchase_reserves_seat(status, hold_expires_at);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
