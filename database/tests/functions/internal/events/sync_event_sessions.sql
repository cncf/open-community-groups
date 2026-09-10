-- Tests synchronizing event sessions and speakers from an update payload.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3a340000-0000-0000-0000-000000000001'
\set eventCategoryID '3a340000-0000-0000-0000-000000000002'
\set eventID '3a340000-0000-0000-0000-000000000003'
\set groupCategoryID '3a340000-0000-0000-0000-000000000004'
\set groupID '3a340000-0000-0000-0000-000000000005'
\set missingSessionID '3a340000-0000-0000-0000-000000000006'
\set session1ID '3a340000-0000-0000-0000-000000000007'
\set session2ID '3a340000-0000-0000-0000-000000000008'
\set user1ID '3a340000-0000-0000-0000-000000000009'
\set user2ID '3a340000-0000-0000-0000-000000000010'
\set user3ID '3a340000-0000-0000-0000-000000000011'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories, event categories and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Users
select fx_user(:'user1ID', jsonb_build_object('username', 'user1-sync-event-sessions'));
select fx_user(:'user2ID', jsonb_build_object('username', 'user2-sync-event-sessions'));
select fx_user(:'user3ID', jsonb_build_object('username', 'user3-sync-event-sessions'));

-- Event
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', '2030-01-01 17:00:00+00',
    'event_kind_id', 'virtual',
    'starts_at', '2030-01-01 09:00:00+00'
));

-- Sessions
insert into session (
    session_id,
    event_id,
    name,
    session_kind_id,
    starts_at,
    ends_at
) values
    (
        :'session1ID',
        :'eventID',
        'Opening Session',
        'virtual',
        '2030-01-01 10:00:00+00',
        '2030-01-01 11:00:00+00'
    ),
    (
        :'session2ID',
        :'eventID',
        'Obsolete Session',
        'in-person',
        '2030-01-01 11:30:00+00',
        '2030-01-01 12:00:00+00'
    );

-- Session speakers
insert into session_speaker (session_id, user_id, featured) values
    (:'session1ID', :'user1ID', false),
    (:'session2ID', :'user2ID', false);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should update existing sessions, insert new ones, and remove omitted ones
select lives_ok(
    format(
        $$select sync_event_sessions(
            '%s'::uuid,
            jsonb_build_object(
                'timezone', 'UTC',
                'sessions', jsonb_build_array(
                    jsonb_build_object(
                        'ends_at', '2030-01-01T11:30:00',
                        'name', 'Opening Session Updated',
                        'session_id', '%s',
                        'speakers', jsonb_build_array(
                            jsonb_build_object(
                                'featured', true,
                                'user_id', '%s'
                            )
                        ),
                        'starts_at', '2030-01-01T10:30:00',
                        'kind', 'virtual'
                    ),
                    jsonb_build_object(
                        'ends_at', '2030-01-01T13:00:00',
                        'name', 'New Session',
                        'speakers', jsonb_build_array(
                            jsonb_build_object(
                                'featured', false,
                                'user_id', '%s'
                            )
                        ),
                        'starts_at', '2030-01-01T12:00:00',
                        'kind', 'in-person'
                    )
                )
            ),
            (select e from event e where e.event_id = '%s'::uuid)
        )$$,
        :'eventID',
        :'session1ID',
        :'user3ID',
        :'user2ID',
        :'eventID'
    ),
    'Should update existing sessions, insert new ones, and remove omitted ones'
);

-- Should update existing session fields
select is(
    (
        select jsonb_build_object(
            'ends_at', ends_at,
            'name', name,
            'starts_at', starts_at
        )
        from session
        where session_id = :'session1ID'::uuid
    ),
    jsonb_build_object(
        'ends_at', '2030-01-01 11:30:00+00'::timestamptz,
        'name', 'Opening Session Updated',
        'starts_at', '2030-01-01 10:30:00+00'::timestamptz
    ),
    'Should update existing session fields'
);

-- Should replace speakers for updated sessions
select is(
    (
        select jsonb_agg(
            jsonb_build_object(
                'featured', featured,
                'user_id', user_id
            )
            order by user_id
        )
        from session_speaker
        where session_id = :'session1ID'::uuid
    ),
    jsonb_build_array(
        jsonb_build_object(
            'featured', true,
            'user_id', :'user3ID'::uuid
        )
    ),
    'Should replace speakers for updated sessions'
);

-- Should insert new sessions from the payload
select is(
    (select count(*) from session where event_id = :'eventID'::uuid and name = 'New Session'),
    1::bigint,
    'Should insert new sessions from the payload'
);

-- Should remove sessions omitted from the payload
select is(
    (select count(*) from session where session_id = :'session2ID'::uuid),
    0::bigint,
    'Should remove sessions omitted from the payload'
);

-- Should leave exactly two sessions after sync
select is(
    (select count(*) from session where event_id = :'eventID'::uuid),
    2::bigint,
    'Should leave exactly two sessions after sync'
);

-- Should delete all sessions when the payload omits them
select lives_ok(
    format(
        $$select sync_event_sessions(
            '%s'::uuid,
            '{"timezone": "UTC"}'::jsonb,
            (select e from event e where e.event_id = '%s'::uuid)
        )$$,
        :'eventID',
        :'eventID'
    ),
    'Should delete all sessions when the payload omits them'
);

-- Should leave no sessions after deleting with an omitted payload
select is(
    (select count(*) from session where event_id = :'eventID'::uuid),
    0::bigint,
    'Should leave no sessions after deleting with an omitted payload'
);

-- Should reject updating a session that does not belong to the event
select throws_ok(
    format(
        $$select sync_event_sessions(
            '%s'::uuid,
            jsonb_build_object(
                'timezone', 'UTC',
                'sessions', jsonb_build_array(
                    jsonb_build_object(
                        'ends_at', '2030-01-01T11:00:00',
                        'name', 'Missing Session',
                        'session_id', '%s',
                        'starts_at', '2030-01-01T10:00:00',
                        'kind', 'virtual'
                    )
                )
            ),
            (select e from event e where e.event_id = '%s'::uuid)
        )$$,
        :'eventID',
        :'missingSessionID',
        :'eventID'
    ),
    format('session %s not found for event %s', :'missingSessionID', :'eventID'),
    'Should reject updating a session that does not belong to the event'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
