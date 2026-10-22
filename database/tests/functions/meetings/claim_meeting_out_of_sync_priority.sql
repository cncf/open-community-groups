-- Tests the order in which meeting sync work is claimed across event, session and orphan cases.
-- Split from claim_meeting_out_of_sync.sql because asserting claim order needs
-- exactly one eligible row per case, while that file seeds several per case.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '7a100000-0000-0000-0000-000000000001'
\set eventCanceledParentID '7a100000-0000-0000-0000-000000000002'
\set eventCategoryID '7a100000-0000-0000-0000-000000000003'
\set eventCreateID '7a100000-0000-0000-0000-000000000004'
\set eventDeleteID '7a100000-0000-0000-0000-000000000005'
\set eventPublishedParentID '7a100000-0000-0000-0000-000000000006'
\set groupCategoryID '7a100000-0000-0000-0000-000000000007'
\set groupID '7a100000-0000-0000-0000-000000000008'
\set meetingOrphanID '7a100000-0000-0000-0000-000000000009'
\set sessionCreateID '7a100000-0000-0000-0000-000000000010'
\set sessionDeleteID '7a100000-0000-0000-0000-000000000011'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories, event categories and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Published event needing create (case 1)
select fx_event(:'eventCreateID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 100,
    'ends_at', current_timestamp + interval '1 day 1 hour',
    'event_kind_id', 'virtual',
    'meeting_in_sync', false,
    'meeting_provider_id', 'zoom',
    'meeting_requested', true,
    'published', true,
    'starts_at', current_timestamp + interval '1 day'
));

-- Published in-sync parent of the session needing create
select fx_event(:'eventPublishedParentID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 100,
    'ends_at', current_timestamp + interval '2 days 1 hour',
    'event_kind_id', 'virtual',
    'meeting_in_sync', true,
    'meeting_provider_id', 'zoom',
    'meeting_requested', true,
    'published', true,
    'starts_at', current_timestamp + interval '2 days'
));

-- Canceled event needing delete (case 3)
select fx_event(:'eventDeleteID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'capacity', 100,
    'ends_at', current_timestamp + interval '3 days 1 hour',
    'event_kind_id', 'virtual',
    'meeting_in_sync', false,
    'meeting_provider_id', 'zoom',
    'meeting_requested', true,
    'starts_at', current_timestamp + interval '3 days'
));

-- Canceled in-sync parent of the session needing delete
select fx_event(:'eventCanceledParentID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'capacity', 100,
    'ends_at', current_timestamp + interval '4 days 1 hour',
    'event_kind_id', 'virtual',
    'meeting_in_sync', true,
    'meeting_provider_id', 'zoom',
    'meeting_requested', true,
    'starts_at', current_timestamp + interval '4 days'
));

-- Session needing create on a published event (case 2)
insert into session (
    ends_at,
    event_id,
    meeting_in_sync,
    meeting_provider_id,
    meeting_requested,
    name,
    session_id,
    session_kind_id,
    starts_at
) values (
    current_timestamp + interval '2 days 30 minutes',
    :'eventPublishedParentID',
    false,
    'zoom',
    true,
    'Priority Session Create',
    :'sessionCreateID',
    'virtual',
    current_timestamp + interval '2 days'
);

-- Session needing delete on a canceled event (case 4)
insert into session (
    ends_at,
    event_id,
    meeting_in_sync,
    meeting_provider_id,
    meeting_requested,
    name,
    session_id,
    session_kind_id,
    starts_at
) values (
    current_timestamp + interval '4 days 30 minutes',
    :'eventCanceledParentID',
    false,
    'zoom',
    true,
    'Priority Session Delete',
    :'sessionDeleteID',
    'virtual',
    current_timestamp + interval '4 days'
);

-- Orphan meeting needing provider cleanup (case 5)
insert into meeting (
    join_url,
    meeting_id,
    meeting_provider_id,
    provider_meeting_id
) values (
    'https://zoom.us/j/priority-orphan',
    :'meetingOrphanID',
    'zoom',
    'priority-orphan'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Each claim keeps only the fields that identify the claimed work

-- Should claim event create/update work first
select is(
    (
        select jsonb_build_object(
            'delete', claim->'delete',
            'event_id', claim->'event_id',
            'meeting_id', claim->'meeting_id',
            'session_id', claim->'session_id'
        )
        from claim_meeting_out_of_sync() as claim
    ),
    jsonb_build_object('delete', false, 'event_id', :'eventCreateID', 'meeting_id', null, 'session_id', null),
    'Should claim event create/update work first'
);

-- Should claim session create/update work after event create/update work
select is(
    (
        select jsonb_build_object(
            'delete', claim->'delete',
            'event_id', claim->'event_id',
            'meeting_id', claim->'meeting_id',
            'session_id', claim->'session_id'
        )
        from claim_meeting_out_of_sync() as claim
    ),
    jsonb_build_object('delete', false, 'event_id', null, 'meeting_id', null, 'session_id', :'sessionCreateID'),
    'Should claim session create/update work after event create/update work'
);

-- Should claim event delete work after all create/update work
select is(
    (
        select jsonb_build_object(
            'delete', claim->'delete',
            'event_id', claim->'event_id',
            'meeting_id', claim->'meeting_id',
            'session_id', claim->'session_id'
        )
        from claim_meeting_out_of_sync() as claim
    ),
    jsonb_build_object('delete', true, 'event_id', :'eventDeleteID', 'meeting_id', null, 'session_id', null),
    'Should claim event delete work after all create/update work'
);

-- Should claim session delete work after event delete work
select is(
    (
        select jsonb_build_object(
            'delete', claim->'delete',
            'event_id', claim->'event_id',
            'meeting_id', claim->'meeting_id',
            'session_id', claim->'session_id'
        )
        from claim_meeting_out_of_sync() as claim
    ),
    jsonb_build_object('delete', true, 'event_id', null, 'meeting_id', null, 'session_id', :'sessionDeleteID'),
    'Should claim session delete work after event delete work'
);

-- Should claim orphan meetings last
select is(
    (
        select jsonb_build_object(
            'delete', claim->'delete',
            'event_id', claim->'event_id',
            'meeting_id', claim->'meeting_id',
            'session_id', claim->'session_id'
        )
        from claim_meeting_out_of_sync() as claim
    ),
    jsonb_build_object('delete', true, 'event_id', null, 'meeting_id', :'meetingOrphanID', 'session_id', null),
    'Should claim orphan meetings last'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
