-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(10);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set bypassSessionID 'ab080000-0000-0000-0000-000000000001'
\set communityID 'ab080000-0000-0000-0000-000000000002'
\set eventCategoryID 'ab080000-0000-0000-0000-000000000003'
\set eventNoBoundsID 'ab080000-0000-0000-0000-000000000004'
\set eventWithBoundsID 'ab080000-0000-0000-0000-000000000005'
\set groupCategoryID 'ab080000-0000-0000-0000-000000000006'
\set groupID 'ab080000-0000-0000-0000-000000000007'
\set sessionID 'ab080000-0000-0000-0000-000000000008'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'communityID',
    'test-community',
    'Test Community',
    'A test community',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Event Category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'Conference');

-- Group Category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    description
) values (
    :'groupID',
    :'communityID',
    :'groupCategoryID',
    'Test Group',
    'test-group',
    'A test group'
);

-- Event with bounds (10:00 to 18:00)
insert into event (
    event_id,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    slug,
    description,
    starts_at,
    ends_at,
    timezone
) values (
    :'eventWithBoundsID',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Event With Bounds',
    'event-with-bounds',
    'An event with start and end times',
    '2030-01-01 10:00:00+00',
    '2030-01-01 18:00:00+00',
    'UTC'
);

-- Event without bounds
insert into event (
    event_id,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    slug,
    description,
    timezone
) values (
    :'eventNoBoundsID',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Event Without Bounds',
    'event-without-bounds',
    'An event without start and end times',
    'UTC'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should succeed when session is within event bounds
select lives_ok(
    format(
        'insert into session (session_id, event_id, name, starts_at, ends_at, session_kind_id) values (%L, %L, ''Valid Session'', ''2030-01-01 11:00:00+00'', ''2030-01-01 12:00:00+00'', ''in-person'')',
        :'sessionID',
        :'eventWithBoundsID'
    ),
    'Should succeed when session is within event bounds'
);

-- Should succeed when session starts_at equals event starts_at (boundary)
select lives_ok(
    format(
        'insert into session (event_id, name, starts_at, ends_at, session_kind_id) values (%L, ''Boundary Start Session'', ''2030-01-01 10:00:00+00'', ''2030-01-01 11:00:00+00'', ''in-person'')',
        :'eventWithBoundsID'
    ),
    'Should succeed when session starts_at equals event starts_at'
);

-- Should succeed when session ends_at equals event ends_at (boundary)
select lives_ok(
    format(
        'insert into session (event_id, name, starts_at, ends_at, session_kind_id) values (%L, ''Boundary End Session'', ''2030-01-01 17:00:00+00'', ''2030-01-01 18:00:00+00'', ''in-person'')',
        :'eventWithBoundsID'
    ),
    'Should succeed when session ends_at equals event ends_at'
);

-- Should succeed when event has no bounds (null starts_at and ends_at)
select lives_ok(
    format(
        'insert into session (event_id, name, starts_at, ends_at, session_kind_id) values (%L, ''Session No Bounds Event'', ''2030-01-01 05:00:00+00'', ''2030-01-01 23:00:00+00'', ''in-person'')',
        :'eventNoBoundsID'
    ),
    'Should succeed when event has no bounds'
);

-- Should fail when session starts_at is before event starts_at
select throws_ok(
    format(
        'insert into session (event_id, name, starts_at, ends_at, session_kind_id) values (%L, ''Early Start Session'', ''2030-01-01 09:00:00+00'', ''2030-01-01 11:00:00+00'', ''in-person'')',
        :'eventWithBoundsID'
    ),
    'session starts_at must be within event bounds',
    'Should fail when session starts_at is before event starts_at'
);

-- Should fail when session starts_at is after event ends_at
select throws_ok(
    format(
        'insert into session (event_id, name, starts_at, ends_at, session_kind_id) values (%L, ''Late Start Session'', ''2030-01-01 19:00:00+00'', ''2030-01-01 20:00:00+00'', ''in-person'')',
        :'eventWithBoundsID'
    ),
    'session starts_at must be within event bounds',
    'Should fail when session starts_at is after event ends_at'
);

-- Should fail when session ends_at is after event ends_at
select throws_ok(
    format(
        'insert into session (event_id, name, starts_at, ends_at, session_kind_id) values (%L, ''Late End Session'', ''2030-01-01 17:00:00+00'', ''2030-01-01 19:00:00+00'', ''in-person'')',
        :'eventWithBoundsID'
    ),
    'session ends_at must be within event bounds',
    'Should fail when session ends_at is after event ends_at'
);

-- Should fail when updating session to violate bounds
select throws_ok(
    format(
        'update session set starts_at = ''2030-01-01 09:00:00+00'' where session_id = %L',
        :'sessionID'
    ),
    'session starts_at must be within event bounds',
    'Should fail when updating session starts_at to before event starts_at'
);

-- Should fail when updating session ends_at to exceed event bounds
select throws_ok(
    format(
        'update session set ends_at = ''2030-01-01 19:00:00+00'' where session_id = %L',
        :'sessionID'
    ),
    'session ends_at must be within event bounds',
    'Should fail when updating session ends_at to after event ends_at'
);

-- Should succeed when bypassing bounds check in local transaction scope
select lives_ok(
    format(
        $sql$
            do $do$
            begin
                perform set_config('ocg.skip_session_bounds_check', 'on', true);

                insert into session (
                    session_id,
                    event_id,
                    name,
                    starts_at,
                    ends_at,
                    session_kind_id
                ) values (
                    %L,
                    %L,
                    'Bypassed Bounds Session',
                    '2030-01-01 05:00:00+00',
                    '2030-01-01 23:00:00+00',
                    'in-person'
                );
            end;
            $do$;
        $sql$,
        :'bypassSessionID',
        :'eventWithBoundsID'
    ),
    'Should succeed when bypassing bounds check in local transaction scope'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
