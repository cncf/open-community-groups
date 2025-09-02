-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set otherCommunityID '00000000-0000-0000-0000-000000000002'
\set categoryID '00000000-0000-0000-0000-000000000011'
\set eventCategoryID '00000000-0000-0000-0000-000000000012'
\set groupID '00000000-0000-0000-0000-000000000031'
\set eventID '00000000-0000-0000-0000-000000000041'
\set user1ID '00000000-0000-0000-0000-000000000051'
\set user2ID '00000000-0000-0000-0000-000000000052'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Communities
insert into community (community_id, name, display_name, host, title, description, header_logo_url, theme) values
    (:'communityID', 'cncf-sea', 'CNCF Seattle', 'sea.example.org', 'Title', 'Desc', 'https://example.com/logo.png', '{}'::jsonb),
    (:'otherCommunityID', 'cncf-ny', 'CNCF NY', 'ny.example.org', 'Title', 'Desc', 'https://example.com/logo.png', '{}'::jsonb);

-- Group category
insert into group_category (group_category_id, name, community_id)
values (:'categoryID', 'Technology', :'communityID');

-- Event category
insert into event_category (event_category_id, name, slug, community_id)
values (:'eventCategoryID', 'Tech', 'tech', :'communityID');

-- Group
insert into "group" (group_id, name, slug, community_id, group_category_id, logo_url, active)
values (:'groupID', 'Test Group', 'test-group', :'communityID', :'categoryID', 'https://example.com/group.png', true);

-- Users
insert into "user" (user_id, email, username, email_verified, auth_hash, community_id, name)
values
    (:'user1ID', 'att1@example.com', 'att1', false, 'h1', :'communityID', 'Att One'),
    (:'user2ID', 'att2@example.com', 'att2', false, 'h2', :'communityID', 'Att Two');

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

-- Attendee
insert into event_attendee (event_id, user_id) values (:'eventID', :'user1ID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- User1 is attendee
select ok(
    is_event_attendee(:'communityID'::uuid, :'eventID'::uuid, :'user1ID'::uuid),
    'is_event_attendee returns true for an attendee'
);

-- User2 is not attendee
select ok(
    not is_event_attendee(:'communityID'::uuid, :'eventID'::uuid, :'user2ID'::uuid),
    'is_event_attendee returns false for a non-attendee'
);

-- Different community should return false
select ok(
    not is_event_attendee(:'otherCommunityID'::uuid, :'eventID'::uuid, :'user1ID'::uuid),
    'is_event_attendee is scoped by community'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
