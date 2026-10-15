-- Tests event UTM view counter constraints.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(12);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'c00b0000-0000-0000-0000-000000000001'
\set deletedEventID 'c00b0000-0000-0000-0000-000000000002'
\set eventCategoryID 'c00b0000-0000-0000-0000-000000000003'
\set eventID 'c00b0000-0000-0000-0000-000000000004'
\set groupCategoryID 'c00b0000-0000-0000-0000-000000000005'
\set groupID 'c00b0000-0000-0000-0000-000000000006'
\set otherDeletedEventID 'c00b0000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community hosting the viewed events
select fx_community(:'communityID');

-- Event category used by the viewed events
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category used by the viewed events group
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group hosting the viewed events
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event deleted while keeping its UTM counter
select fx_event(:'deletedEventID', :'groupID', :'eventCategoryID');

-- Event receiving the counters written by the constraint scenarios
select fx_event(:'eventID', :'groupID', :'eventCategoryID');

-- Other event deleted while keeping an identical UTM counter
select fx_event(:'otherDeletedEventID', :'groupID', :'eventCategoryID');

-- UTM counter kept after its event is deleted
insert into event_views_utm (event_id, day, total, utm_source)
values (:'deletedEventID', '2026-01-01', 1, 'newsletter');

-- UTM counter whose key is duplicated
insert into event_views_utm (event_id, day, total, utm_source)
values (:'eventID', '2026-01-01', 1, 'newsletter');

-- Other UTM counter kept after its event is deleted
insert into event_views_utm (event_id, day, total, utm_source)
values (:'otherDeletedEventID', '2026-01-01', 1, 'newsletter');

-- ============================================================================
-- TESTS
-- ============================================================================
-- Should accept UTM values of 50 characters
select lives_ok(
    format(
        $$
            insert into event_views_utm (event_id, day, total, utm_campaign, utm_medium, utm_source)
            values (%L::uuid, '2026-01-02', 1, repeat('c', 50), repeat('m', 50), repeat('s', 50))
        $$,
        :'eventID'
    ),
    'Should accept UTM values of 50 characters'
);

-- Should accept counters attributed only to a campaign
select lives_ok(
    format(
        $$
            insert into event_views_utm (event_id, day, total, utm_campaign)
            values (%L::uuid, '2026-01-02', 1, 'spring-launch')
        $$,
        :'eventID'
    ),
    'Should accept counters attributed only to a campaign'
);

-- Should keep identical counters distinct after their events are deleted
select lives_ok(
    format(
        $$delete from event where event_id in (%L::uuid, %L::uuid)$$,
        :'deletedEventID',
        :'otherDeletedEventID'
    ),
    'Should delete events with identical UTM counters'
);
select is(
    (
        select count(*)::int
        from event_views_utm
        where event_id is null
        and utm_source = 'newsletter'
    ),
    2,
    'Should keep identical counters distinct after their events are deleted'
);

-- Should reject counters without a source or a campaign
select throws_ok(
    format(
        $$
            insert into event_views_utm (event_id, day, total, utm_medium)
            values (%L::uuid, '2026-01-03', 1, 'email')
        $$,
        :'eventID'
    ),
    '23514',
    'new row for relation "event_views_utm" violates check constraint "event_views_utm_attribution_chk"',
    'Should reject counters without a source or a campaign'
);

-- Should reject duplicate counters for the same event, day and UTM parameters
select throws_ok(
    format(
        $$
            insert into event_views_utm (event_id, day, total, utm_source)
            values (%L::uuid, '2026-01-01', 1, 'newsletter')
        $$,
        :'eventID'
    ),
    '23505',
    null,
    'Should reject duplicate counters for the same event, day and UTM parameters'
);

-- Should reject UTM campaigns longer than 50 characters
select throws_ok(
    format(
        $$
            insert into event_views_utm (event_id, day, total, utm_campaign, utm_source)
            values (%L::uuid, '2026-01-03', 1, repeat('c', 51), 'newsletter')
        $$,
        :'eventID'
    ),
    '23514',
    null,
    'Should reject UTM campaigns longer than 50 characters'
);

-- Should reject UTM campaigns with unsupported characters
select throws_ok(
    format(
        $$
            insert into event_views_utm (event_id, day, total, utm_campaign, utm_source)
            values (%L::uuid, '2026-01-03', 1, 'Spring Launch', 'newsletter')
        $$,
        :'eventID'
    ),
    '23514',
    null,
    'Should reject UTM campaigns with unsupported characters'
);

-- Should reject UTM mediums longer than 50 characters
select throws_ok(
    format(
        $$
            insert into event_views_utm (event_id, day, total, utm_medium, utm_source)
            values (%L::uuid, '2026-01-03', 1, repeat('m', 51), 'newsletter')
        $$,
        :'eventID'
    ),
    '23514',
    null,
    'Should reject UTM mediums longer than 50 characters'
);

-- Should reject UTM mediums with unsupported characters
select throws_ok(
    format(
        $$
            insert into event_views_utm (event_id, day, total, utm_medium, utm_source)
            values (%L::uuid, '2026-01-03', 1, 'E-mail!', 'newsletter')
        $$,
        :'eventID'
    ),
    '23514',
    null,
    'Should reject UTM mediums with unsupported characters'
);

-- Should reject UTM sources longer than 50 characters
select throws_ok(
    format(
        $$
            insert into event_views_utm (event_id, day, total, utm_source)
            values (%L::uuid, '2026-01-03', 1, repeat('s', 51))
        $$,
        :'eventID'
    ),
    '23514',
    null,
    'Should reject UTM sources longer than 50 characters'
);

-- Should reject UTM sources with unsupported characters
select throws_ok(
    format(
        $$
            insert into event_views_utm (event_id, day, total, utm_source)
            values (%L::uuid, '2026-01-03', 1, 'News Letter')
        $$,
        :'eventID'
    ),
    '23514',
    null,
    'Should reject UTM sources with unsupported characters'
);


-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
