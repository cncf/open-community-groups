-- Tests closing event co-host invitations.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set approvedGroupID 'e5040000-0000-0000-0000-000000000001'
\set communityID 'e5040000-0000-0000-0000-000000000002'
\set eventCategoryID 'e5040000-0000-0000-0000-000000000003'
\set eventID 'e5040000-0000-0000-0000-000000000004'
\set groupCategoryID 'e5040000-0000-0000-0000-000000000005'
\set groupID 'e5040000-0000-0000-0000-000000000006'
\set pendingGroupID 'e5040000-0000-0000-0000-000000000007'
\set rejectedGroupID 'e5040000-0000-0000-0000-000000000008'
\set userID 'e5040000-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, groups, event and actor
select fx_community(:'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'approvedGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_group(:'pendingGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'rejectedGroupID', :'communityID', :'groupCategoryID');
select fx_event(:'eventID', :'groupID', :'eventCategoryID');
select fx_user(:'userID');

-- Co-host rows covering closable and untouched statuses
insert into event_cohost (
    approved_at,
    event_cohost_status_id,
    event_id,
    group_id
) values (
    '2025-01-01 00:00:00+00',
    'approved',
    :'eventID',
    :'approvedGroupID'
);
insert into event_cohost (event_id, group_id)
values (:'eventID', :'pendingGroupID');
insert into event_cohost (
    event_cohost_status_id,
    event_id,
    group_id
) values (
    'rejected',
    :'eventID',
    :'rejectedGroupID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject invalid close statuses
select throws_ok(
    format(
        'select close_event_cohosts(%L::uuid, %L::uuid, ''removed'')',
        :'userID',
        :'eventID'
    ),
    'invalid event co-host close status',
    'Should reject invalid close statuses'
);

-- Should close pending and approved co-hosts for event cancellation
select lives_ok(
    format(
        'select close_event_cohosts(%L::uuid, %L::uuid, ''event-canceled'')',
        :'userID',
        :'eventID'
    ),
    'Should close pending and approved co-hosts for event cancellation'
);

select results_eq(
    format(
        $$
        select group_id, event_cohost_status_id, approved_at is not null
        from event_cohost
        where event_id = %L::uuid
        order by group_id
        $$,
        :'eventID'
    ),
    format(
        $$
        values
            (%L::uuid, 'event-canceled', true),
            (%L::uuid, 'event-canceled', false),
            (%L::uuid, 'rejected', false)
        $$,
        :'approvedGroupID',
        :'pendingGroupID',
        :'rejectedGroupID'
    ),
    'Should close pending and approved co-hosts for event cancellation'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
