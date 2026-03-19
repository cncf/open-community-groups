-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000011'
\set communityID '00000000-0000-0000-0000-000000000001'
\set event1ID '00000000-0000-0000-0000-000000000041'
\set eventCategoryID '00000000-0000-0000-0000-000000000012'
\set groupID '00000000-0000-0000-0000-000000000021'
\set user1ID '00000000-0000-0000-0000-000000000031'
\set user2ID '00000000-0000-0000-0000-000000000032'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'c1', 'C1', 'd', 'https://e/logo.png', 'https://e/bm.png', 'https://e/b.png');

-- Group category
insert into group_category (group_category_id, name, community_id)
values (:'categoryID', 'Tech', :'communityID');

-- Event category
insert into event_category (event_category_id, name, community_id)
values (:'eventCategoryID', 'General', :'communityID');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'categoryID', 'G1', 'g1');

-- Users
insert into "user" (auth_hash, email, user_id, username, company, name, photo_url, title)
values
    (gen_random_bytes(32), 'alice@example.com', :'user1ID', 'alice', 'Cloud Corp', 'Alice', 'https://e/u1.png', 'Principal Engineer'),
    (gen_random_bytes(32), 'bob@example.com', :'user2ID', 'bob', null, null, 'https://e/u2.png', null);

-- Event
insert into event (event_id, name, slug, description, timezone, event_category_id, event_kind_id, group_id, published, canceled, deleted, capacity, waitlist_enabled)
values
    (:'event1ID', 'E1', 'e1', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', true, false, false, 1, true);

-- Waitlist entries
insert into event_waitlist (event_id, user_id, created_at)
values
    (:'event1ID', :'user1ID', '2024-01-01 00:00:00+00'),
    (:'event1ID', :'user2ID', '2024-01-02 00:00:00+00');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return waitlist entries with expected fields and FIFO order
select is(
    search_event_waitlist(
        :'groupID'::uuid,
        '{"event_id":"00000000-0000-0000-0000-000000000041","limit":50,"offset":0}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'waitlist', '[
            {"created_at": 1704067200, "user_id": "00000000-0000-0000-0000-000000000031", "username": "alice", "company": "Cloud Corp", "name": "Alice", "photo_url": "https://e/u1.png", "title": "Principal Engineer"},
            {"created_at": 1704153600, "user_id": "00000000-0000-0000-0000-000000000032", "username": "bob", "company": null, "name": null, "photo_url": "https://e/u2.png", "title": null}
        ]'::jsonb,
        'total', 2
    ),
    'Should return waitlist entries with expected fields and FIFO order'
);

-- Should return paginated waitlist entries when limit and offset are provided
select is(
    search_event_waitlist(
        :'groupID'::uuid,
        '{"event_id":"00000000-0000-0000-0000-000000000041","limit":1,"offset":1}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'waitlist', '[
            {"created_at": 1704153600, "user_id": "00000000-0000-0000-0000-000000000032", "username": "bob", "company": null, "name": null, "photo_url": "https://e/u2.png", "title": null}
        ]'::jsonb,
        'total', 2
    ),
    'Should return paginated waitlist entries when limit and offset are provided'
);

-- Should return empty list when no event_id provided
select is(
    search_event_waitlist(
        :'groupID'::uuid,
        '{"limit":50,"offset":0}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'waitlist', '[]'::jsonb,
        'total', 0
    ),
    'Should return empty list when no event_id provided'
);

-- Should return empty list for non-existing event
select is(
    search_event_waitlist(
        :'groupID'::uuid,
        '{"event_id":"00000000-0000-0000-0000-999999999999","limit":50,"offset":0}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'waitlist', '[]'::jsonb,
        'total', 0
    ),
    'Should return empty list for non-existing event'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
