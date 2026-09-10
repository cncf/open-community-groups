-- Tests evaluating whether events accept enrollment.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept active published future events
select is(
    event_accepts_enrollment(
        jsonb_populate_record(null::event, jsonb_build_object(
            'canceled', false,
            'deleted', false,
            'ends_at', current_timestamp + interval '2 hours',
            'published', true,
            'starts_at', current_timestamp + interval '1 hour'
        )),
        jsonb_populate_record(null::"group", jsonb_build_object('active', true))
    ),
    true,
    'Should accept active published future events'
);

-- Should accept dateless events
select is(
    event_accepts_enrollment(
        jsonb_populate_record(null::event, jsonb_build_object(
            'canceled', false,
            'deleted', false,
            'published', true
        )),
        jsonb_populate_record(null::"group", jsonb_build_object('active', true))
    ),
    true,
    'Should accept dateless events'
);

-- Should accept events with future starts and no explicit end
select is(
    event_accepts_enrollment(
        jsonb_populate_record(null::event, jsonb_build_object(
            'canceled', false,
            'deleted', false,
            'published', true,
            'starts_at', current_timestamp + interval '1 hour'
        )),
        jsonb_populate_record(null::"group", jsonb_build_object('active', true))
    ),
    true,
    'Should accept events with future starts and no explicit end'
);

-- Should reject canceled events
select is(
    event_accepts_enrollment(
        jsonb_populate_record(null::event, jsonb_build_object(
            'canceled', true,
            'deleted', false,
            'published', true,
            'starts_at', current_timestamp + interval '1 hour'
        )),
        jsonb_populate_record(null::"group", jsonb_build_object('active', true))
    ),
    false,
    'Should reject canceled events'
);

-- Should reject deleted events
select is(
    event_accepts_enrollment(
        jsonb_populate_record(null::event, jsonb_build_object(
            'canceled', false,
            'deleted', true,
            'published', false,
            'starts_at', current_timestamp + interval '1 hour'
        )),
        jsonb_populate_record(null::"group", jsonb_build_object('active', true))
    ),
    false,
    'Should reject deleted events'
);

-- Should reject ended events
select is(
    event_accepts_enrollment(
        jsonb_populate_record(null::event, jsonb_build_object(
            'canceled', false,
            'deleted', false,
            'ends_at', current_timestamp - interval '1 hour',
            'published', true,
            'starts_at', current_timestamp - interval '2 hours'
        )),
        jsonb_populate_record(null::"group", jsonb_build_object('active', true))
    ),
    false,
    'Should reject ended events'
);

-- Should reject events in inactive groups
select is(
    event_accepts_enrollment(
        jsonb_populate_record(null::event, jsonb_build_object(
            'canceled', false,
            'deleted', false,
            'published', true,
            'starts_at', current_timestamp + interval '1 hour'
        )),
        jsonb_populate_record(null::"group", jsonb_build_object('active', false))
    ),
    false,
    'Should reject events in inactive groups'
);

-- Should reject unpublished events
select is(
    event_accepts_enrollment(
        jsonb_populate_record(null::event, jsonb_build_object(
            'canceled', false,
            'deleted', false,
            'published', false,
            'starts_at', current_timestamp + interval '1 hour'
        )),
        jsonb_populate_record(null::"group", jsonb_build_object('active', true))
    ),
    false,
    'Should reject unpublished events'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
