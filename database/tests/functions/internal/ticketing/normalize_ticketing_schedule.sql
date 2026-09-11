-- Tests normalizing price window and discount code schedules for comparison.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(12);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should compare a fractional and a whole-second spelling of one instant as equal
select is(
    normalize_ticketing_schedule('{"amount_minor": 2500, "starts_at": "2030-01-01T10:00:00.000Z"}'::jsonb),
    normalize_ticketing_schedule('{"amount_minor": 2500, "starts_at": "2030-01-01T10:00:00Z"}'::jsonb),
    'Should compare a fractional and a whole-second spelling of one instant as equal'
);

-- Should compare every offset spelling of one instant as equal
select is(
    normalize_ticketing_schedule('{"starts_at": "2030-01-01T10:00:00Z"}'::jsonb),
    normalize_ticketing_schedule('{"starts_at": "2030-01-01T10:00:00+00:00"}'::jsonb),
    'Should compare Z and +00:00 spellings as equal'
);
select is(
    normalize_ticketing_schedule('{"starts_at": "2030-01-01T10:00:00Z"}'::jsonb),
    normalize_ticketing_schedule('{"starts_at": "2030-01-01T12:00:00+02:00"}'::jsonb),
    'Should compare Z and +02:00 spellings as equal'
);
select is(
    normalize_ticketing_schedule('{"starts_at": "2030-01-01T10:00:00Z"}'::jsonb),
    normalize_ticketing_schedule('{"starts_at": "2030-01-01T05:00:00-05:00"}'::jsonb),
    'Should compare Z and -05:00 spellings as equal'
);

-- Should compare sub-second-only differences as equal by design
select is(
    normalize_ticketing_schedule('{"starts_at": "2030-01-01T10:00:00.100Z"}'::jsonb),
    normalize_ticketing_schedule('{"starts_at": "2030-01-01T10:00:00.900Z"}'::jsonb),
    'Should compare sub-second-only differences as equal by design'
);

-- Should distinguish the same wall-clock time in different offsets
select isnt(
    normalize_ticketing_schedule('{"starts_at": "2030-01-01T10:00:00Z"}'::jsonb),
    normalize_ticketing_schedule('{"starts_at": "2030-01-01T10:00:00+02:00"}'::jsonb),
    'Should distinguish the same wall-clock time in different offsets'
);

-- Should drop missing and JSON null schedule keys
select is(
    normalize_ticketing_schedule('{"amount_minor": 2500}'::jsonb),
    '{"amount_minor": 2500}'::jsonb,
    'Should drop missing schedule keys'
);
select is(
    normalize_ticketing_schedule('{"amount_minor": 2500, "ends_at": null, "starts_at": null}'::jsonb),
    '{"amount_minor": 2500}'::jsonb,
    'Should drop JSON null schedule keys'
);

-- Should encode an end-only schedule as epoch seconds
select is(
    normalize_ticketing_schedule('{"amount_minor": 2500, "ends_at": "2030-03-01T10:00:00Z"}'::jsonb),
    '{"amount_minor": 2500, "ends_at": 1898589600}'::jsonb,
    'Should encode an end-only schedule as epoch seconds'
);

-- Should encode a start-only schedule as epoch seconds
select is(
    normalize_ticketing_schedule('{"amount_minor": 2500, "starts_at": "2030-01-01T10:00:00Z"}'::jsonb),
    '{"amount_minor": 2500, "starts_at": 1893492000}'::jsonb,
    'Should encode a start-only schedule as epoch seconds'
);

-- Should encode both schedule bounds and keep every other key untouched
select is(
    normalize_ticketing_schedule(
        '{
            "active": true,
            "code": "EARLY",
            "ends_at": "2030-03-01T10:00:00Z",
            "event_discount_code_id": "3b030000-0000-0000-0000-000000000099",
            "starts_at": "2030-01-01T10:00:00Z",
            "total_available": 10
        }'::jsonb
    ),
    '{
        "active": true,
        "code": "EARLY",
        "ends_at": 1898589600,
        "event_discount_code_id": "3b030000-0000-0000-0000-000000000099",
        "starts_at": 1893492000,
        "total_available": 10
    }'::jsonb,
    'Should encode both schedule bounds and keep every other key untouched'
);

-- Should reject a malformed timestamp
select throws_ok(
    $$select normalize_ticketing_schedule('{"starts_at": "not-a-timestamp"}'::jsonb)$$,
    '22007',
    null,
    'Should reject a malformed timestamp'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
