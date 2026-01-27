-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000011'
\set communityID '00000000-0000-0000-0000-000000000001'
\set event1ID '00000000-0000-0000-0000-000000000041'
\set event2ID '00000000-0000-0000-0000-000000000042'
\set eventCategoryID '00000000-0000-0000-0000-000000000012'
\set groupID '00000000-0000-0000-0000-000000000021'
\set user1ID '00000000-0000-0000-0000-000000000031'
\set user2ID '00000000-0000-0000-0000-000000000032'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'c', 'C', 'd', 'https://e/logo.png', 'https://e/banner_mobile.png', 'https://e/banner.png');

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
insert into "user" (auth_hash, email, user_id, username, company, name, photo_url, title)
values
    ('h', 'alice@example.com', :'user1ID', 'alice', 'Cloud Corp', 'Alice', 'https://example.com/a.png', 'Principal Engineer'),
    ('h', 'bob@example.com', :'user2ID', 'bob', null, null, 'https://example.com/b.png', null);

-- Events
insert into event (event_id, name, slug, description, timezone, event_category_id, event_kind_id, group_id, published, canceled, deleted)
values
    (:'event1ID', 'E1', 'e1', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', true, false, false),
    (:'event2ID', 'E2', 'e2', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', true, false, false);

-- Attendees
insert into event_attendee (event_id, user_id, checked_in, created_at, checked_in_at)
values
    (:'event1ID', :'user1ID', true,  '2024-01-01 00:00:00+00', '2024-01-01 10:00:00+00'),
    (:'event1ID', :'user2ID', false, '2024-01-02 00:00:00+00', null),
    (:'event2ID', :'user2ID', true,  '2024-01-03 00:00:00+00', '2024-01-03 15:00:00+00');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return attendees for event1 with expected fields and order
select is(
    search_event_attendees(:'groupID'::uuid, '{"event_id":"00000000-0000-0000-0000-000000000041"}'::jsonb)::jsonb,
    jsonb_build_object(
        'attendees', '[
            {"checked_in": true,  "created_at": 1704067200, "user_id": "00000000-0000-0000-0000-000000000031", "username": "alice", "checked_in_at": 1704103200, "company": "Cloud Corp", "name": "Alice", "photo_url": "https://example.com/a.png", "title": "Principal Engineer"},
            {"checked_in": false, "created_at": 1704153600, "user_id": "00000000-0000-0000-0000-000000000032", "username": "bob",   "checked_in_at": null,       "company": null,        "name": null,    "photo_url": "https://example.com/b.png", "title": null}
        ]'::jsonb,
        'total', 2
    ),
    'Should return attendees for event1 with expected fields and order'
);

-- Should return paginated attendees when limit and offset are provided
select is(
    search_event_attendees(
        :'groupID'::uuid,
        '{"event_id":"00000000-0000-0000-0000-000000000041","limit":1,"offset":1}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'attendees', '[
            {"checked_in": false, "created_at": 1704153600, "user_id": "00000000-0000-0000-0000-000000000032", "username": "bob", "checked_in_at": null, "company": null, "name": null, "photo_url": "https://example.com/b.png", "title": null}
        ]'::jsonb,
        'total', 2
    ),
    'Should return paginated attendees when limit and offset are provided'
);

-- Should return attendees for event2
select is(
    search_event_attendees(:'groupID'::uuid, '{"event_id":"00000000-0000-0000-0000-000000000042"}'::jsonb)::jsonb,
    jsonb_build_object(
        'attendees', '[
            {"checked_in": true, "created_at": 1704240000, "user_id": "00000000-0000-0000-0000-000000000032", "username": "bob", "checked_in_at": 1704294000, "company": null, "name": null, "photo_url": "https://example.com/b.png", "title": null}
        ]'::jsonb,
        'total', 1
    ),
    'Should return attendees for event2'
);

-- Should return empty list when no event_id provided
select is(
    search_event_attendees(:'groupID'::uuid, '{}'::jsonb)::jsonb,
    jsonb_build_object(
        'attendees', '[]'::jsonb,
        'total', 0
    ),
    'Should return empty list when no event_id provided'
);

-- Should return empty list for non-existing event
select is(
    search_event_attendees(:'groupID'::uuid, '{"event_id":"00000000-0000-0000-0000-999999999999"}'::jsonb)::jsonb,
    jsonb_build_object(
        'attendees', '[]'::jsonb,
        'total', 0
    ),
    'Should return empty list for non-existing event'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
