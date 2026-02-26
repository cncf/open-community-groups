-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000011'
\set community2ID '00000000-0000-0000-0000-000000000002'
\set communityID '00000000-0000-0000-0000-000000000001'
\set eventCategoryID '00000000-0000-0000-0000-000000000012'
\set eventID '00000000-0000-0000-0000-000000000041'
\set groupID '00000000-0000-0000-0000-000000000031'
\set user1ID '00000000-0000-0000-0000-000000000051'
\set user2ID '00000000-0000-0000-0000-000000000052'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url) values
    (:'communityID', 'cncf-sea', 'CNCF Seattle', 'Desc', 'https://example.com/logo.png', 'https://example.com/banner_mobile.png', 'https://example.com/banner.png'),
    (:'community2ID', 'cncf-ny', 'CNCF NY', 'Desc', 'https://example.com/logo.png', 'https://example.com/banner_mobile.png', 'https://example.com/banner.png');

-- Group Category
insert into group_category (group_category_id, name, community_id)
values (:'categoryID', 'Technology', :'communityID');

-- Event Category
insert into event_category (event_category_id, name, community_id)
values (:'eventCategoryID', 'Tech', :'communityID');

-- Group
insert into "group" (group_id, name, slug, community_id, group_category_id, logo_url, active)
values (:'groupID', 'Test Group', 'test-group', :'communityID', :'categoryID', 'https://example.com/group.png', true);

-- User
insert into "user" (user_id, auth_hash, email, username, name)
values
    (:'user1ID', 'h1', 'att1@example.com', 'att1', 'Att One'),
    (:'user2ID', 'h2', 'att2@example.com', 'att2', 'Att Two'),
    ('00000000-0000-0000-0000-000000000053', 'h3', 'att3@example.com', 'att3', 'Att Three');

-- Event
insert into event (
    event_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    group_id,
    published
) values (
    :'eventID',
    'Event',
    'event',
    'desc',
    'UTC',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    true
);

-- Event Attendee - user1 is checked in
insert into event_attendee (event_id, user_id, checked_in, checked_in_at) values (:'eventID', :'user1ID', true, current_timestamp);

-- Event Attendee - user2 is not checked in
insert into event_attendee (event_id, user_id, checked_in) values (:'eventID', :'user2ID', false);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return (true, true) for checked-in attendee
select is(
    (
        select row(is_attendee, is_checked_in)::text
        from is_event_attendee(:'communityID'::uuid, :'eventID'::uuid, :'user1ID'::uuid)
    ),
    '(t,t)',
    'Should return (true, true) for a checked-in attendee'
);

-- Should return (true, false) for attendee not checked in
select is(
    (
        select row(is_attendee, is_checked_in)::text
        from is_event_attendee(:'communityID'::uuid, :'eventID'::uuid, :'user2ID'::uuid)
    ),
    '(t,f)',
    'Should return (true, false) for an attendee not checked in'
);

-- Should return (false, false) when scoped by wrong community
select is(
    (
        select row(is_attendee, is_checked_in)::text
        from is_event_attendee(:'community2ID'::uuid, :'eventID'::uuid, :'user1ID'::uuid)
    ),
    '(f,f)',
    'Should return (false, false) when scoped by wrong community'
);

-- Should return (false, false) for non-attendee
select is(
    (
        select row(is_attendee, is_checked_in)::text
        from is_event_attendee(:'communityID'::uuid, :'eventID'::uuid, '00000000-0000-0000-0000-000000000053'::uuid)
    ),
    '(f,f)',
    'Should return (false, false) for a non-attendee'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
