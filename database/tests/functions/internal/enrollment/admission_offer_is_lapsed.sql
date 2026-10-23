-- Tests the lapsed admission offer predicate.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should not report active offers with a future deadline as lapsed
select is(
    array_agg(status order by status),
    null::text[],
    'Should not report active offers with a future deadline as lapsed'
)
from unnest(array['checkout_pending', 'pending']) as status
where admission_offer_is_lapsed(status, current_timestamp + interval '1 minute');

-- Should not report terminal offers past their deadline as lapsed
select is(
    array_agg(status order by status),
    null::text[],
    'Should not report terminal offers past their deadline as lapsed'
)
from unnest(array['canceled', 'completed', 'declined', 'expired']) as status
where admission_offer_is_lapsed(status, current_timestamp - interval '1 hour');

-- Should report active offers past their deadline as lapsed
select is(
    array_agg(status order by status),
    array['checkout_pending', 'pending'],
    'Should report active offers past their deadline as lapsed'
)
from unnest(array[
    'canceled', 'checkout_pending', 'completed', 'declined', 'expired', 'pending'
]) as status
where admission_offer_is_lapsed(status, current_timestamp - interval '1 hour');

-- Should report active offers whose deadline is now as lapsed
select is(
    array_agg(status order by status),
    array['checkout_pending', 'pending'],
    'Should report active offers whose deadline is now as lapsed'
)
from unnest(array['checkout_pending', 'pending']) as status
where admission_offer_is_lapsed(status, current_timestamp);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
