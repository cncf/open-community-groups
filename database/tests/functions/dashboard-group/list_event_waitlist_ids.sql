-- Tests listing event waitlist identifiers.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3a1e0000-0000-0000-0000-000000000001'
\set eventCategoryID '3a1e0000-0000-0000-0000-000000000002'
\set eventID '3a1e0000-0000-0000-0000-000000000003'
\set groupCategoryID '3a1e0000-0000-0000-0000-000000000004'
\set groupID '3a1e0000-0000-0000-0000-000000000005'
\set missingEventID '3a1e0000-0000-0000-0000-000000000006'
\set missingGroupID '3a1e0000-0000-0000-0000-000000000007'
\set otherGroupID '3a1e0000-0000-0000-0000-000000000008'
\set ticketTypeID '3a1e0000-0000-0000-0000-000000000012'
\set user0ID '3a1e0000-0000-0000-0000-000000000009'
\set user1ID '3a1e0000-0000-0000-0000-000000000010'
\set user2ID '3a1e0000-0000-0000-0000-000000000011'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories, event categories, users and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'user0ID');
select fx_user(:'user1ID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_group(:'otherGroupID', :'communityID', :'groupCategoryID');

-- Users
select fx_user(:'user2ID', jsonb_build_object('email_verified', false));

-- Event
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 1,
    'published', true,
    'waitlist_enabled', true
));

-- Ticket tier shared by the event waitlist
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object('seats_total', 1));

-- Waitlist entries
insert into event_waitlist (event_id, event_ticket_type_id, user_id)
values
    (:'eventID', :'ticketTypeID', :'user0ID'),
    (:'eventID', :'ticketTypeID', :'user1ID'),
    (:'eventID', :'ticketTypeID', :'user2ID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return verified waitlist users only
select is(
    list_event_waitlist_ids(:'groupID'::uuid, :'eventID'::uuid),
    array[:'user0ID'::uuid, :'user1ID'::uuid],
    'Returns verified waitlist users only'
);

-- Should return empty list for event without waitlist entries
select is(
    list_event_waitlist_ids(:'missingGroupID'::uuid, :'missingEventID'::uuid),
    array[]::uuid[],
    'Returns empty list for event without waitlist entries'
);

-- Should return empty list when wrong group_id is provided
select is(
    list_event_waitlist_ids(:'otherGroupID'::uuid, :'eventID'::uuid),
    array[]::uuid[],
    'Returns empty list when wrong group_id is provided'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
