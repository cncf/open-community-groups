-- Tests canceling approved event co-hosting.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set cohostGroupID 'e50f0000-0000-0000-0000-000000000001'
\set communityID 'e50f0000-0000-0000-0000-000000000002'
\set eventCategoryID 'e50f0000-0000-0000-0000-000000000003'
\set eventID 'e50f0000-0000-0000-0000-000000000004'
\set groupCategoryID 'e50f0000-0000-0000-0000-000000000005'
\set groupID 'e50f0000-0000-0000-0000-000000000006'
\set invitationID 'e50f0000-0000-0000-0000-000000000007'
\set userID 'e50f0000-0000-0000-0000-000000000008'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, groups, event and actor
select fx_community(:'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'cohostGroupID', :'communityID', :'groupCategoryID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));
select fx_user(:'userID');

-- Approved co-host invitation
insert into event_cohost (
    approved_at,
    event_cohost_status_id,
    event_id,
    group_id,
    invitation_id
) values (
    '2025-01-01 00:00:00+00',
    'approved',
    :'eventID',
    :'cohostGroupID',
    :'invitationID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should cancel approved co-hosting on a published event
select is(
    cancel_event_cohost(:'userID'::uuid, :'cohostGroupID'::uuid, :'invitationID'::uuid)::jsonb @> format(
        '{"cohost_group_id":"%s","event_id":"%s","invitation_id":"%s","owner_group_id":"%s"}',
        :'cohostGroupID',
        :'eventID',
        :'invitationID',
        :'groupID'
    )::jsonb,
    true,
    'Should cancel approved co-hosting on a published event'
);

select results_eq(
    format(
        $$
        select event_cohost_status_id, approved_at is not null
        from event_cohost
        where event_id = %L::uuid
        $$,
        :'eventID'
    ),
    $$ values ('canceled', true) $$,
    'Should cancel approved co-hosting on a published event'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
