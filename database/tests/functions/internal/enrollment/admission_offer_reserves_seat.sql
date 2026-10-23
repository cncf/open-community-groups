-- Tests the admission offer seat-reservation predicate.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should not reserve seats for active offers past their deadline
select is(
    array_agg(status order by status),
    null::text[],
    'Should not reserve seats for active offers past their deadline'
)
from unnest(array['checkout_pending', 'pending']) as status
where admission_offer_reserves_seat(status, current_timestamp - interval '1 minute');

-- Should not reserve seats for active offers whose deadline is now
select is(
    array_agg(status order by status),
    null::text[],
    'Should not reserve seats for active offers whose deadline is now'
)
from unnest(array['checkout_pending', 'pending']) as status
where admission_offer_reserves_seat(status, current_timestamp);

-- Should not reserve seats for terminal offers with a future deadline
select is(
    array_agg(status order by status),
    null::text[],
    'Should not reserve seats for terminal offers with a future deadline'
)
from unnest(array['canceled', 'completed', 'declined', 'expired']) as status
where admission_offer_reserves_seat(status, current_timestamp + interval '1 hour');

-- Should reserve seats for active offers with a future deadline
select is(
    array_agg(status order by status),
    array['checkout_pending', 'pending'],
    'Should reserve seats for active offers with a future deadline'
)
from unnest(array[
    'canceled', 'checkout_pending', 'completed', 'declined', 'expired', 'pending'
]) as status
where admission_offer_reserves_seat(status, current_timestamp + interval '1 hour');

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
