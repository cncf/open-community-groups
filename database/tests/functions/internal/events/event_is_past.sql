-- Tests reporting whether events are over.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should report dateless events as not past
select is(
    event_is_past(jsonb_populate_record(null::event, jsonb_build_object())),
    false,
    'Should report dateless events as not past'
);

-- Should report ended events as past
select is(
    event_is_past(jsonb_populate_record(null::event, jsonb_build_object(
        'ends_at', current_timestamp - interval '1 hour',
        'starts_at', current_timestamp - interval '2 hours'
    ))),
    true,
    'Should report ended events as past'
);

-- Should report events ending now as not past
select is(
    event_is_past(jsonb_populate_record(null::event, jsonb_build_object(
        'ends_at', current_timestamp,
        'starts_at', current_timestamp - interval '1 hour'
    ))),
    false,
    'Should report events ending now as not past'
);

-- Should report events in progress as not past
select is(
    event_is_past(jsonb_populate_record(null::event, jsonb_build_object(
        'ends_at', current_timestamp + interval '1 hour',
        'starts_at', current_timestamp - interval '1 hour'
    ))),
    false,
    'Should report events in progress as not past'
);

-- Should report events with future ends as not past
select is(
    event_is_past(jsonb_populate_record(null::event, jsonb_build_object(
        'ends_at', current_timestamp + interval '2 hours',
        'starts_at', current_timestamp + interval '1 hour'
    ))),
    false,
    'Should report events with future ends as not past'
);

-- Should report events with future starts and no end as not past
select is(
    event_is_past(jsonb_populate_record(null::event, jsonb_build_object(
        'starts_at', current_timestamp + interval '1 hour'
    ))),
    false,
    'Should report events with future starts and no end as not past'
);

-- Should report started events without an end as past
select is(
    event_is_past(jsonb_populate_record(null::event, jsonb_build_object(
        'starts_at', current_timestamp - interval '1 hour'
    ))),
    true,
    'Should report started events without an end as past'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
