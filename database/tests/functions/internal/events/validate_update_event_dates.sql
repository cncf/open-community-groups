-- Tests validating update payload dates against the stored event and sessions.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(14);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3a4a0000-0000-0000-0000-000000000003'
\set eventCategoryID '3a4a0000-0000-0000-0000-000000000004'
\set groupCategoryID '3a4a0000-0000-0000-0000-000000000005'
\set groupID '3a4a0000-0000-0000-0000-000000000006'
\set liveEventID '3a4a0000-0000-0000-0000-000000000002'
\set liveSessionID '3a4a0000-0000-0000-0000-000000000001'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories and group
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Live event that started an hour ago
select fx_event(:'liveEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp + interval '2 hours',
    'starts_at', current_timestamp - interval '1 hour'
));

-- Session of the live event that already finished
insert into session (session_id, event_id, name, session_kind_id, starts_at, ends_at)
values (
    :'liveSessionID',
    :'liveEventID',
    'Finished Session',
    'in-person',
    current_timestamp - interval '45 minutes',
    current_timestamp - interval '15 minutes'
);

-- ============================================================================
-- TESTS
-- ============================================================================
-- Should accept a future event that stays in the future
select lives_ok(
    $$select validate_update_event_dates(
        '{
            "starts_at": "2030-01-01T10:00:00",
            "ends_at": "2030-01-01T11:00:00",
            "timezone": "UTC"
        }'::jsonb,
        jsonb_populate_record(null::event, '{
            "ends_at": "2030-01-01T11:00:00+00:00",
            "starts_at": "2030-01-01T10:00:00+00:00"
        }'::jsonb)
    )$$,
    'Should accept a future event that stays in the future'
);

-- Should reject a future event that moves into the past
select throws_ok(
    $$select validate_update_event_dates(
        jsonb_build_object(
            'starts_at', to_char(current_timestamp at time zone 'UTC' - interval '1 hour', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'timezone', 'UTC'
        ),
        jsonb_populate_record(null::event, jsonb_build_object(
            'ends_at', current_timestamp + interval '1 day' + interval '1 hour',
            'starts_at', current_timestamp + interval '1 day'
        ))
    )$$,
    'OCG01',
    'event starts_at cannot be in the past',
    'Should reject a future event that moves into the past'
);

-- Should reject registration windows where the open date is after the close date
select throws_ok(
    $$select validate_update_event_dates(
        jsonb_build_object(
            'starts_at', to_char(current_timestamp at time zone 'UTC' + interval '3 days', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'registration_starts_at', to_char(current_timestamp at time zone 'UTC' + interval '2 days', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'registration_ends_at', to_char(current_timestamp at time zone 'UTC' + interval '1 day', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'timezone', 'UTC'
        ),
        jsonb_populate_record(null::event, jsonb_build_object(
            'ends_at', current_timestamp + interval '4 days' + interval '1 hour',
            'starts_at', current_timestamp + interval '4 days'
        ))
    )$$,
    'OCG01',
    'registration starts_at must be before registration ends_at',
    'Should reject registration windows where the open date is after the close date'
);

-- Should reject registration windows where the open date equals the close date
select throws_ok(
    $$select validate_update_event_dates(
        jsonb_build_object(
            'starts_at', to_char(current_timestamp at time zone 'UTC' + interval '3 days', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'registration_starts_at', to_char(current_timestamp at time zone 'UTC' + interval '2 days', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'registration_ends_at', to_char(current_timestamp at time zone 'UTC' + interval '2 days', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'timezone', 'UTC'
        ),
        jsonb_populate_record(null::event, jsonb_build_object(
            'ends_at', current_timestamp + interval '4 days' + interval '1 hour',
            'starts_at', current_timestamp + interval '4 days'
        ))
    )$$,
    'OCG01',
    'registration starts_at must be before registration ends_at',
    'Should reject registration windows where the open date equals the close date'
);

-- Should reject registration close dates after the event start
select throws_ok(
    $$select validate_update_event_dates(
        jsonb_build_object(
            'starts_at', to_char(current_timestamp at time zone 'UTC' + interval '1 day', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'registration_ends_at', to_char(current_timestamp at time zone 'UTC' + interval '2 days', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'timezone', 'UTC'
        ),
        jsonb_populate_record(null::event, jsonb_build_object(
            'ends_at', current_timestamp + interval '4 days' + interval '1 hour',
            'starts_at', current_timestamp + interval '4 days'
        ))
    )$$,
    'OCG01',
    'registration ends_at cannot be after event starts_at',
    'Should reject registration close dates after the event start'
);

-- Should reject open-only registration windows that open after the event start
select throws_ok(
    $$select validate_update_event_dates(
        jsonb_build_object(
            'starts_at', to_char(current_timestamp at time zone 'UTC' + interval '1 day', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'registration_starts_at', to_char(current_timestamp at time zone 'UTC' + interval '2 days', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'timezone', 'UTC'
        ),
        jsonb_populate_record(null::event, jsonb_build_object(
            'ends_at', current_timestamp + interval '4 days' + interval '1 hour',
            'starts_at', current_timestamp + interval '4 days'
        ))
    )$$,
    'OCG01',
    'registration starts_at cannot be after event starts_at',
    'Should reject open-only registration windows that open after the event start'
);

-- Should reject a past event that moves into the future
select throws_ok(
    $$select validate_update_event_dates(
        jsonb_build_object(
            'starts_at', to_char(current_timestamp at time zone 'UTC' + interval '1 hour', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'timezone', 'UTC'
        ),
        jsonb_populate_record(null::event, jsonb_build_object(
            'ends_at', current_timestamp - interval '1 day',
            'starts_at', current_timestamp - interval '2 day'
        ))
    )$$,
    'OCG01',
    'event starts_at cannot be in the future',
    'Should reject a past event that moves into the future'
);

-- Should reject a live event that moves earlier than its current start
select throws_ok(
    $$select validate_update_event_dates(
        jsonb_build_object(
            'starts_at', to_char(current_timestamp at time zone 'UTC' - interval '2 hour', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'timezone', 'UTC'
        ),
        jsonb_populate_record(null::event, jsonb_build_object(
            'ends_at', current_timestamp + interval '1 hour',
            'starts_at', current_timestamp - interval '1 hour'
        ))
    )$$,
    'OCG01',
    'event starts_at cannot be earlier than current value',
    'Should reject a live event that moves earlier than its current start'
);

-- Should reject a dateless event that moves into the past
select throws_ok(
    $$select validate_update_event_dates(
        jsonb_build_object(
            'starts_at', to_char(current_timestamp at time zone 'UTC' - interval '1 hour', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'timezone', 'UTC'
        ),
        null::event
    )$$,
    'OCG01',
    'event starts_at cannot be in the past',
    'Should reject a dateless event that moves into the past'
);

-- Should accept a dateless event that moves into the future
select lives_ok(
    $$select validate_update_event_dates(
        jsonb_build_object(
            'starts_at', to_char(current_timestamp at time zone 'UTC' + interval '1 day', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'ends_at', to_char(current_timestamp at time zone 'UTC' + interval '1 day' + interval '1 hour', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'timezone', 'UTC'
        ),
        null::event
    )$$,
    'Should accept a dateless event that moves into the future'
);

-- Should reject a future session that moves into the past
select throws_ok(
    $$select validate_update_event_dates(
        jsonb_build_object(
            'timezone', 'UTC',
            'sessions', jsonb_build_array(
                jsonb_build_object(
                    'starts_at', to_char(current_timestamp at time zone 'UTC' - interval '1 hour', 'YYYY-MM-DD"T"HH24:MI:SS')
                )
            )
        ),
        jsonb_populate_record(null::event, jsonb_build_object(
            'ends_at', current_timestamp + interval '1 day' + interval '1 hour',
            'starts_at', current_timestamp + interval '1 day'
        ))
    )$$,
    'OCG01',
    'session starts_at cannot be in the past',
    'Should reject a future session that moves into the past'
);

-- Should accept a live event update when a session keeps its current past dates
select lives_ok(
    format($$select validate_update_event_dates(
        jsonb_build_object(
            'timezone', 'UTC',
            'sessions', jsonb_build_array(
                jsonb_build_object(
                    'session_id', %L,
                    'starts_at', to_char(
                        current_timestamp at time zone 'UTC' - interval '45 minutes',
                        'YYYY-MM-DD"T"HH24:MI:SS'
                    ),
                    'ends_at', to_char(
                        current_timestamp at time zone 'UTC' - interval '15 minutes',
                        'YYYY-MM-DD"T"HH24:MI:SS'
                    )
                )
            )
        ),
        (select e from event e where e.event_id = %L)
    )$$, :'liveSessionID', :'liveEventID'),
    'Should accept a live event update when a session keeps its current past dates'
);

-- Should accept a live event that keeps its current start at whole-second precision
select lives_ok(
    $$select validate_update_event_dates(
        jsonb_build_object(
            'starts_at', to_char(current_timestamp at time zone 'UTC' - interval '1 hour', 'YYYY-MM-DD"T"HH24:MI:SS'),
            'timezone', 'UTC'
        ),
        jsonb_populate_record(null::event, jsonb_build_object(
            'ends_at', current_timestamp + interval '1 hour',
            'starts_at', date_trunc('second', current_timestamp) - interval '1 hour' + interval '400 milliseconds'
        ))
    )$$,
    'Should accept a live event that keeps its current start at whole-second precision'
);

-- Should reject a non-UTC future event that moves into the past
select throws_ok(
    $$select validate_update_event_dates(
        jsonb_build_object(
            'starts_at', to_char(
                current_timestamp at time zone 'Asia/Kolkata' - interval '1 hour',
                'YYYY-MM-DD"T"HH24:MI:SS'
            ),
            'timezone', 'Asia/Kolkata'
        ),
        jsonb_populate_record(null::event, jsonb_build_object(
            'ends_at', current_timestamp + interval '1 day' + interval '1 hour',
            'starts_at', current_timestamp + interval '1 day'
        ))
    )$$,
    'OCG01',
    'event starts_at cannot be in the past',
    'Should reject a non-UTC future event that moves into the past'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
