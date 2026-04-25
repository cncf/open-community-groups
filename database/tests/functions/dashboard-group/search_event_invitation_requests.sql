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
\set event2ID '00000000-0000-0000-0000-000000000042'
\set eventCategoryID '00000000-0000-0000-0000-000000000012'
\set groupID '00000000-0000-0000-0000-000000000021'
\set user1ID '00000000-0000-0000-0000-000000000031'
\set user2ID '00000000-0000-0000-0000-000000000032'
\set user3ID '00000000-0000-0000-0000-000000000033'

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
    (gen_random_bytes(32), 'bob@example.com', :'user2ID', 'bob', null, null, 'https://e/u2.png', null),
    (gen_random_bytes(32), 'carol@example.com', :'user3ID', 'carol', null, 'Carol', null, 'Designer');

-- Events
insert into event (
    event_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    group_id,
    attendee_approval_required,
    published,
    canceled,
    deleted
)
values
    (:'event1ID', 'E1', 'e1', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', true, true, false, false),
    (:'event2ID', 'E2', 'e2', 'd', 'UTC', :'eventCategoryID', 'in-person', :'groupID', true, true, false, false);

-- Invitation requests
insert into event_invitation_request (event_id, user_id, created_at, status, reviewed_at, reviewed_by)
values
    (:'event1ID', :'user1ID', '2024-01-01 00:00:00+00', 'accepted', '2024-01-01 01:00:00+00', :'user3ID'),
    (:'event1ID', :'user2ID', '2024-01-02 00:00:00+00', 'pending', null, null),
    (:'event1ID', :'user3ID', '2024-01-03 00:00:00+00', 'rejected', '2024-01-03 01:00:00+00', :'user1ID'),
    (:'event2ID', :'user3ID', '2024-01-04 00:00:00+00', 'pending', null, null);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return invitation requests with pending requests first
select is(
    search_event_invitation_requests(
        :'groupID'::uuid,
        '{"event_id":"00000000-0000-0000-0000-000000000041","limit":50,"offset":0}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'invitation_requests', '[
            {"created_at": 1704153600, "invitation_request_status": "pending", "user_id": "00000000-0000-0000-0000-000000000032", "username": "bob", "company": null, "name": null, "photo_url": "https://e/u2.png", "reviewed_at": null, "title": null},
            {"created_at": 1704067200, "invitation_request_status": "accepted", "user_id": "00000000-0000-0000-0000-000000000031", "username": "alice", "company": "Cloud Corp", "name": "Alice", "photo_url": "https://e/u1.png", "reviewed_at": 1704070800, "title": "Principal Engineer"},
            {"created_at": 1704240000, "invitation_request_status": "rejected", "user_id": "00000000-0000-0000-0000-000000000033", "username": "carol", "company": null, "name": "Carol", "photo_url": null, "reviewed_at": 1704243600, "title": "Designer"}
        ]'::jsonb,
        'total', 3
    ),
    'Should return invitation requests with pending requests first'
);

-- Should return paginated invitation requests when limit and offset are provided
select is(
    search_event_invitation_requests(
        :'groupID'::uuid,
        '{"event_id":"00000000-0000-0000-0000-000000000041","limit":1,"offset":1}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'invitation_requests', '[
            {"created_at": 1704067200, "invitation_request_status": "accepted", "user_id": "00000000-0000-0000-0000-000000000031", "username": "alice", "company": "Cloud Corp", "name": "Alice", "photo_url": "https://e/u1.png", "reviewed_at": 1704070800, "title": "Principal Engineer"}
        ]'::jsonb,
        'total', 3
    ),
    'Should return paginated invitation requests when limit and offset are provided'
);

-- Should return empty list when no event_id provided
select is(
    search_event_invitation_requests(
        :'groupID'::uuid,
        '{"limit":50,"offset":0}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'invitation_requests', '[]'::jsonb,
        'total', 0
    ),
    'Should return empty list when no event_id provided'
);

-- Should return empty list for non-existing event
select is(
    search_event_invitation_requests(
        :'groupID'::uuid,
        '{"event_id":"00000000-0000-0000-0000-999999999999","limit":50,"offset":0}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'invitation_requests', '[]'::jsonb,
        'total', 0
    ),
    'Should return empty list for non-existing event'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
