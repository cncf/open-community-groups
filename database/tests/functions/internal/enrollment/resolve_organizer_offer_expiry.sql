-- Tests resolving organizer admission offer expiry.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should bound dateless events by twenty-four hours
select is(
    resolve_organizer_offer_expiry(jsonb_populate_record(null::event, '{}'::jsonb)),
    current_timestamp + interval '24 hours',
    'Should bound dateless events by twenty-four hours'
);

-- Should bound future events after twenty-four hours
select is(
    resolve_organizer_offer_expiry(jsonb_populate_record(null::event, jsonb_build_object(
        'starts_at', current_timestamp + interval '2 days'
    ))),
    current_timestamp + interval '24 hours',
    'Should bound future events after twenty-four hours'
);

-- Should bound future events by starts within twenty-four hours
select is(
    resolve_organizer_offer_expiry(jsonb_populate_record(null::event, jsonb_build_object(
        'starts_at', current_timestamp + interval '12 hours'
    ))),
    current_timestamp + interval '12 hours',
    'Should bound future events by starts within twenty-four hours'
);

-- Should bound in-progress events after twenty-four hours
select is(
    resolve_organizer_offer_expiry(jsonb_populate_record(null::event, jsonb_build_object(
        'ends_at', current_timestamp + interval '2 days',
        'starts_at', current_timestamp - interval '1 hour'
    ))),
    current_timestamp + interval '24 hours',
    'Should bound in-progress events after twenty-four hours'
);

-- Should bound in-progress events by ends within twenty-four hours
select is(
    resolve_organizer_offer_expiry(jsonb_populate_record(null::event, jsonb_build_object(
        'ends_at', current_timestamp + interval '12 hours',
        'starts_at', current_timestamp - interval '1 hour'
    ))),
    current_timestamp + interval '12 hours',
    'Should bound in-progress events by ends within twenty-four hours'
);

-- Should bound in-progress events without ends by twenty-four hours
select is(
    resolve_organizer_offer_expiry(jsonb_populate_record(null::event, jsonb_build_object(
        'starts_at', current_timestamp - interval '1 hour'
    ))),
    current_timestamp + interval '24 hours',
    'Should bound in-progress events without ends by twenty-four hours'
);

-- Should reject ended events
select throws_ok(
    $$
        select resolve_organizer_offer_expiry(jsonb_populate_record(null::event, jsonb_build_object(
            'ends_at', current_timestamp - interval '1 hour',
            'starts_at', current_timestamp - interval '2 hours'
        )))
    $$,
    'OCG01',
    'event not found or inactive',
    'Should reject ended events'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
