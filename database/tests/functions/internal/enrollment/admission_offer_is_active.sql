-- Tests the admission offer active-status predicate.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should treat pending and checkout-pending offers as active
select is(
    array_agg(status order by status),
    array['checkout_pending', 'pending'],
    'Should treat pending and checkout-pending offers as active'
)
from unnest(array['canceled', 'checkout_pending', 'completed', 'declined', 'expired', 'pending']) as status
where admission_offer_is_active(status);

-- Should treat settled offers as inactive
select is(
    array_agg(status order by status),
    array['canceled', 'completed', 'declined', 'expired'],
    'Should treat settled offers as inactive'
)
from unnest(array['canceled', 'checkout_pending', 'completed', 'declined', 'expired', 'pending']) as status
where not admission_offer_is_active(status);

-- Should return null for a null status
select is(
    admission_offer_is_active(null),
    null::boolean,
    'Should return null for a null status'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
