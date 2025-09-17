-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set categoryID '00000000-0000-0000-0000-000000000011'
\set eventCategoryID '00000000-0000-0000-0000-000000000012'
\set groupID '00000000-0000-0000-0000-000000000021'
\set user1ID '00000000-0000-0000-0000-000000000031'
\set user2ID '00000000-0000-0000-0000-000000000032'
\set event1ID '00000000-0000-0000-0000-000000000041'
\set event2ID '00000000-0000-0000-0000-000000000042'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, host, title, description, header_logo_url, theme)
values (:'communityID', 'c', 'C', 'c.example.org', 't', 'd', 'https://e/logo.png', '{}'::jsonb);

-- Group category
insert into group_category (group_category_id, name, community_id)
values (:'categoryID', 'Tech', :'communityID');

-- Event category
insert into event_category (event_category_id, name, slug, community_id)
values (:'eventCategoryID', 'General', 'general', :'communityID');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug, active, deleted)
values (:'groupID', :'communityID', :'categoryID', 'G', 'g', true, false);

-- Users
insert into "user" (
    auth_hash,
    community_id,
    company,
    email,
    name,
    photo_url,
    title,
    user_id,
    username
)
values
    ('h', :'communityID', 'Cloud Corp', 'alice@example.com', 'Alice', 'https://example.com/a.png', 'Principal Engineer', :'user1ID', 'alice'),
    ('h', :'communityID', null, 'bob@example.com', null, 'https://example.com/b.png', null, :'user2ID', 'bob');

-- Events
insert into event (event_id, name, slug, description, timezone, event_category_id, event_kind_id, group_id, published, canceled, deleted)
values
    (:'event1ID', 'E1', 'e1', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', true, false, false),
    (:'event2ID', 'E2', 'e2', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', true, false, false);

-- Attendees
insert into event_attendee (event_id, user_id, checked_in, created_at)
values
    (:'event1ID', :'user1ID', true,  '2024-01-01 00:00:00+00'),
    (:'event1ID', :'user2ID', false, '2024-01-02 00:00:00+00'),
    (:'event2ID', :'user2ID', true,  '2024-01-03 00:00:00+00');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Test: returns attendees for event1 ordered by name/username with fields
select is(
    search_event_attendees(:'groupID'::uuid, '{"event_id":"00000000-0000-0000-0000-000000000041"}'::jsonb)::jsonb,
    '[
        {"checked_in": true,  "created_at": 1704067200, "username": "alice", "company": "Cloud Corp", "name": "Alice", "photo_url": "https://example.com/a.png", "title": "Principal Engineer"},
        {"checked_in": false, "created_at": 1704153600, "username": "bob",   "company": null, "name": null,     "photo_url": "https://example.com/b.png", "title": null}
    ]'::jsonb,
    'Should return attendees for event1 with expected fields and order'
);

-- Test: returns attendees for event2
select is(
    search_event_attendees(:'groupID'::uuid, '{"event_id":"00000000-0000-0000-0000-000000000042"}'::jsonb)::jsonb,
    '[
        {"checked_in": true, "created_at": 1704240000, "username": "bob", "company": null, "name": null, "photo_url": "https://example.com/b.png", "title": null}
    ]'::jsonb,
    'Should return attendees for event2'
);

-- Test: missing event_id should return empty array
select is(
    search_event_attendees(:'groupID'::uuid, '{}'::jsonb)::text,
    '[]',
    'Should return empty list when no event_id provided'
);

-- Test: non-existing event should return empty array
select is(
    search_event_attendees(:'groupID'::uuid, '{"event_id":"00000000-0000-0000-0000-999999999999"}'::jsonb)::text,
    '[]',
    'Should return empty list for non-existing event'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
