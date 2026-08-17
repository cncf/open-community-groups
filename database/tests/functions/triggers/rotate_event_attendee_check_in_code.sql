-- Tests attendee check-in credential generation and confirmation rotation.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3a2e0000-0000-0000-0000-000000000001'
\set eventCategoryID '3a2e0000-0000-0000-0000-000000000002'
\set eventID '3a2e0000-0000-0000-0000-000000000003'
\set groupCategoryID '3a2e0000-0000-0000-0000-000000000004'
\set groupID '3a2e0000-0000-0000-0000-000000000005'
\set pendingUserID '3a2e0000-0000-0000-0000-000000000006'
\set secondUserID '3a2e0000-0000-0000-0000-000000000007'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community containing the trigger fixture
insert into community (
    community_id,
    banner_mobile_url,
    banner_url,
    description,
    display_name,
    logo_url,
    name
) values (
    :'communityID',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'A test community',
    'Test Community',
    'https://example.com/logo.png',
    'test-community'
);

-- Group category used by the trigger fixture
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Event category used by the trigger fixture
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'General');

-- Users carrying independently generated credentials
insert into "user" (user_id, auth_hash, email, email_verified, username) values
    (:'pendingUserID', 'hash-1', 'pending@example.com', true, 'pending'),
    (:'secondUserID', 'hash-2', 'second@example.com', true, 'second');

-- Group owning the trigger fixture event
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Test Group', 'test-group');

-- Event owning the trigger fixture attendees
insert into event (
    event_id,
    description,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    slug,
    timezone
) values (
    :'eventID',
    'An event for trigger tests',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Trigger Event',
    'trigger-event',
    'UTC'
);

-- Pending and confirmed attendees with generated credentials
insert into event_attendee (event_id, user_id, status) values
    (:'eventID', :'pendingUserID', 'invitation-pending'),
    (:'eventID', :'secondUserID', 'confirmed');

-- Capture the pending attendee's original credential
select check_in_code as "checkInCode"
from event_attendee
where event_id = :'eventID'::uuid
and user_id = :'pendingUserID'::uuid \gset original_

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should generate globally unique attendee credentials
select is(
    (
        select count(distinct check_in_code)::int
        from event_attendee
        where event_id = :'eventID'::uuid
    ),
    2,
    'Should generate globally unique attendee credentials'
);

-- Should rotate a credential when attendance becomes confirmed
update event_attendee
set status = 'confirmed'
where event_id = :'eventID'::uuid
and user_id = :'pendingUserID'::uuid;

select isnt(
    (
        select check_in_code
        from event_attendee
        where event_id = :'eventID'::uuid
        and user_id = :'pendingUserID'::uuid
    ),
    :'original_checkInCode'::uuid,
    'Should rotate a credential when attendance becomes confirmed'
);

-- Capture the rotated credential before a stable-status update
select check_in_code as "checkInCode"
from event_attendee
where event_id = :'eventID'::uuid
and user_id = :'pendingUserID'::uuid \gset rotated_

-- Should preserve a credential while attendance remains confirmed
update event_attendee
set status = 'confirmed'
where event_id = :'eventID'::uuid
and user_id = :'pendingUserID'::uuid;

select is(
    (
        select check_in_code
        from event_attendee
        where event_id = :'eventID'::uuid
        and user_id = :'pendingUserID'::uuid
    ),
    :'rotated_checkInCode'::uuid,
    'Should preserve a credential while attendance remains confirmed'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
