-- Tests atomic guarded deletion for recurring event series.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorID 'd1020000-0000-0000-0000-000000000001'
\set communityID 'd1020000-0000-0000-0000-000000000002'
\set eligibleEventOneID 'd1020000-0000-0000-0000-000000000003'
\set eligibleEventTwoID 'd1020000-0000-0000-0000-000000000004'
\set eligibleSeriesID 'd1020000-0000-0000-0000-000000000005'
\set eventCategoryID 'd1020000-0000-0000-0000-000000000006'
\set groupCategoryID 'd1020000-0000-0000-0000-000000000007'
\set groupID 'd1020000-0000-0000-0000-000000000008'
\set guardedAllowedEventID 'd1020000-0000-0000-0000-000000000009'
\set guardedBlockedEventID 'd1020000-0000-0000-0000-000000000010'
\set guardedSeriesID 'd1020000-0000-0000-0000-000000000011'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning both recurring series
insert into community (
    banner_mobile_url,
    banner_url,
    community_id,
    description,
    display_name,
    logo_url,
    name
) values (
    'https://example.test/mobile.png',
    'https://example.test/banner.png',
    :'communityID',
    'Community',
    'Community',
    'https://example.test/logo.png',
    'community'
);

-- Group category owning the test group
insert into group_category (community_id, group_category_id, name)
values (:'communityID', :'groupCategoryID', 'Category');

-- Event category used by recurring events
insert into event_category (community_id, event_category_id, name)
values (:'communityID', :'eventCategoryID', 'Events');

-- Group owning both recurring series
insert into "group" (community_id, group_category_id, group_id, name, slug)
values (:'communityID', :'groupCategoryID', :'groupID', 'Group', 'group');

-- Actor deleting the recurring events
insert into "user" (auth_hash, email, user_id, username)
values ('hash', 'actor@example.test', :'actorID', 'actor');

-- Series containing two eligible unused drafts
insert into event_series (
    created_by,
    event_series_id,
    group_id,
    recurrence_additional_occurrences,
    recurrence_anchor_starts_at,
    recurrence_pattern,
    timezone
) values (
    :'actorID',
    :'eligibleSeriesID',
    :'groupID',
    1,
    now() + interval '1 day',
    'weekly',
    'UTC'
);

-- Series containing an eligible occurrence followed by a blocked occurrence
insert into event_series (
    created_by,
    event_series_id,
    group_id,
    recurrence_additional_occurrences,
    recurrence_anchor_starts_at,
    recurrence_pattern,
    timezone
) values (
    :'actorID',
    :'guardedSeriesID',
    :'groupID',
    1,
    now() + interval '3 days',
    'weekly',
    'UTC'
);

-- Eligible unused draft occurrences
insert into event (
    description,
    event_category_id,
    event_id,
    event_kind_id,
    event_series_id,
    group_id,
    name,
    slug,
    starts_at,
    timezone
) values
    (
        'One',
        :'eventCategoryID',
        :'eligibleEventOneID',
        'in-person',
        :'eligibleSeriesID',
        :'groupID',
        'One',
        'one',
        now() + interval '1 day',
        'UTC'
    ),
    (
        'Two',
        :'eventCategoryID',
        :'eligibleEventTwoID',
        'in-person',
        :'eligibleSeriesID',
        :'groupID',
        'Two',
        'two',
        now() + interval '2 days',
        'UTC'
    );

-- Guarded series whose first occurrence is already canceled
insert into event (
    canceled,
    description,
    event_category_id,
    event_id,
    event_kind_id,
    event_series_id,
    group_id,
    name,
    published,
    slug,
    starts_at,
    timezone
) values (
    true,
    'Allowed',
    :'eventCategoryID',
    :'guardedAllowedEventID',
    'in-person',
    :'guardedSeriesID',
    :'groupID',
    'Allowed',
    false,
    'allowed',
    now() + interval '3 days',
    'UTC'
);

-- Guarded series whose second occurrence must be canceled first
insert into event (
    description,
    event_category_id,
    event_id,
    event_kind_id,
    event_series_id,
    group_id,
    name,
    published,
    slug,
    starts_at,
    timezone
) values (
    'Blocked',
    :'eventCategoryID',
    :'guardedBlockedEventID',
    'in-person',
    :'guardedSeriesID',
    :'groupID',
    'Blocked',
    true,
    'blocked',
    now() + interval '4 days',
    'UTC'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should delete an eligible draft series atomically
select lives_ok(
    format(
        'select delete_event_series_events(%L, %L, %L::uuid[])',
        :'actorID',
        :'groupID',
        array[:'eligibleEventOneID', :'eligibleEventTwoID']
    ),
    'Should delete an eligible draft series atomically'
);
select is(
    (
        select count(*)::int
        from event
        where event_series_id = :'eligibleSeriesID'
        and deleted
    ),
    2,
    'Should delete every eligible occurrence'
);
select is(
    (
        select count(*)::int
        from event
        where event_series_id = :'eligibleSeriesID'
        and not published
    ),
    2,
    'Should unpublish every deleted occurrence'
);
select is(
    (select count(*)::int from audit_log where action = 'event_deleted'),
    2,
    'Should audit every deleted occurrence'
);

-- Should reject replaying deletion for inactive occurrences
select throws_ok(
    format(
        'select delete_event_series_events(%L, %L, %L::uuid[])',
        :'actorID',
        :'groupID',
        array[:'eligibleEventOneID', :'eligibleEventTwoID']
    ),
    'one or more events were not found or inactive',
    'Should reject replaying deletion for inactive occurrences'
);

-- Should roll back every occurrence when one deletion is blocked
select throws_ok(
    format(
        'select delete_event_series_events(%L, %L, %L::uuid[])',
        :'actorID',
        :'groupID',
        array[:'guardedAllowedEventID', :'guardedBlockedEventID']
    ),
    'event must be canceled and all payment work settled before deletion',
    'Should reject a series containing a blocked occurrence'
);
select is(
    (
        select count(*)::int
        from event
        where event_series_id = :'guardedSeriesID'
        and deleted
    ),
    0,
    'Should roll back every occurrence when one deletion is blocked'
);
select is(
    (select count(*)::int from audit_log where action = 'event_deleted'),
    2,
    'Should roll back audit rows for a blocked series deletion'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
