-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set eventCategoryID '00000000-0000-0000-0000-000000000011'
\set eventID '00000000-0000-0000-0000-000000000021'
\set groupCategoryID '00000000-0000-0000-0000-000000000031'
\set groupID '00000000-0000-0000-0000-000000000041'
\set missingSessionID '00000000-0000-0000-0000-000000000061'
\set session1ID '00000000-0000-0000-0000-000000000051'
\set session2ID '00000000-0000-0000-0000-000000000052'
\set user1ID '00000000-0000-0000-0000-000000000071'
\set user2ID '00000000-0000-0000-0000-000000000072'
\set user3ID '00000000-0000-0000-0000-000000000073'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'community-1', 'Community 1', 'Test community', 'https://e/logo.png', 'https://e/banner-mobile.png', 'https://e/banner.png');

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Group 1', 'group-1');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'Meetup');

-- Users
insert into "user" (user_id, auth_hash, email, username, email_verified, name) values
    (:'user1ID', gen_random_bytes(32), 'user1@example.com', 'user1', true, 'User 1'),
    (:'user2ID', gen_random_bytes(32), 'user2@example.com', 'user2', true, 'User 2'),
    (:'user3ID', gen_random_bytes(32), 'user3@example.com', 'user3', true, 'User 3');

-- Event
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    starts_at,
    ends_at
) values (
    :'eventID',
    :'groupID',
    'Sessions Event',
    'sessions-event',
    'Event used for session sync tests',
    'UTC',
    :'eventCategoryID',
    'virtual',
    '2030-01-01 09:00:00+00',
    '2030-01-01 17:00:00+00'
);

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
            get_event_full('%s'::uuid, '%s'::uuid, '%s'::uuid)::jsonb
        )$$,
        :'eventID',
        :'session1ID',
        :'user3ID',
        :'user2ID',
        :'communityID',
        :'groupID',
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
            get_event_full('%s'::uuid, '%s'::uuid, '%s'::uuid)::jsonb
        )$$,
        :'eventID',
        :'communityID',
        :'groupID',
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
            get_event_full('%s'::uuid, '%s'::uuid, '%s'::uuid)::jsonb
        )$$,
        :'eventID',
        :'missingSessionID',
        :'communityID',
        :'groupID',
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
