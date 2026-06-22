-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '3a2f0000-0000-0000-0000-000000000001'
\set event1ID '3a2f0000-0000-0000-0000-000000000002'
\set event2ID '3a2f0000-0000-0000-0000-000000000003'
\set eventCategoryID '3a2f0000-0000-0000-0000-000000000004'
\set group2ID '3a2f0000-0000-0000-0000-000000000005'
\set groupCategoryID '3a2f0000-0000-0000-0000-000000000006'
\set groupID '3a2f0000-0000-0000-0000-000000000007'
\set missingEventID '3a2f0000-0000-0000-0000-000000000008'
\set user1ID '3a2f0000-0000-0000-0000-000000000009'
\set user2ID '3a2f0000-0000-0000-0000-000000000010'
\set user3ID '3a2f0000-0000-0000-0000-000000000011'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'allianceID',
    'invitation-search-alliance',
    'Invitation Search Alliance',
    'A test alliance for invitation search',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, alliance_id, name)
values (:'groupCategoryID', :'allianceID', 'Tech');

-- Event category
insert into event_category (event_category_id, alliance_id, name)
values (:'eventCategoryID', :'allianceID', 'General');

-- Groups
insert into "group" (group_id, alliance_id, group_category_id, name, slug)
values
    (:'groupID', :'allianceID', :'groupCategoryID', 'Invitation Group', 'invitation-group'),
    (:'group2ID', :'allianceID', :'groupCategoryID', 'Other Group', 'other-group');

-- Users
insert into "user" (
    user_id,
    auth_hash,
    email,
    username,
    company,
    name,
    photo_url,
    title
) values (
    :'user1ID',
    gen_random_bytes(32),
    'alice@example.com',
    'alice',
    'Cloud Corp',
    'Alice',
    'https://example.com/alice.png',
    'Principal Engineer'
), (
    :'user2ID',
    gen_random_bytes(32),
    'bob@example.com',
    'bob',
    null,
    null,
    'https://example.com/bob.png',
    null
), (
    :'user3ID',
    gen_random_bytes(32),
    'carol@example.com',
    'carol',
    null,
    'Carol',
    null,
    'Designer'
);

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
values (
    :'event1ID',
    'Invitation Event',
    'invitation-event',
    'An event for invitation requests',
    'UTC',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    true,
    true,
    false,
    false
), (
    :'event2ID',
    'Other Invitation Event',
    'other-invitation-event',
    'Another event for invitation requests',
    'UTC',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    true,
    true,
    false,
    false
);

-- Invitation requests
insert into event_invitation_request (
    event_id,
    user_id,
    created_at,
    reviewed_at,
    reviewed_by,
    status
) values (
    :'event1ID',
    :'user1ID',
    '2024-01-01 00:00:00+00',
    '2024-01-01 01:00:00+00',
    :'user3ID',
    'accepted'
), (
    :'event1ID',
    :'user2ID',
    '2024-01-02 00:00:00+00',
    null,
    null,
    'pending'
), (
    :'event1ID',
    :'user3ID',
    '2024-01-03 00:00:00+00',
    '2024-01-03 01:00:00+00',
    :'user1ID',
    'rejected'
), (
    :'event2ID',
    :'user3ID',
    '2024-01-04 00:00:00+00',
    null,
    null,
    'pending'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return invitation requests with pending requests first
select is(
    search_event_invitation_requests(
        :'groupID'::uuid,
        jsonb_build_object('event_id', :'event1ID'::uuid, 'limit', 50, 'offset', 0)
    )::jsonb,
    jsonb_build_object(
        'invitation_requests', '[
            {"created_at": 1704153600, "invitation_request_status": "pending", "user_id": "3a2f0000-0000-0000-0000-000000000010", "username": "bob", "company": null, "name": null, "photo_url": "https://example.com/bob.png", "reviewed_at": null, "title": null},
            {"created_at": 1704067200, "invitation_request_status": "accepted", "user_id": "3a2f0000-0000-0000-0000-000000000009", "username": "alice", "company": "Cloud Corp", "name": "Alice", "photo_url": "https://example.com/alice.png", "reviewed_at": 1704070800, "title": "Principal Engineer"},
            {"created_at": 1704240000, "invitation_request_status": "rejected", "user_id": "3a2f0000-0000-0000-0000-000000000011", "username": "carol", "company": null, "name": "Carol", "photo_url": null, "reviewed_at": 1704243600, "title": "Designer"}
        ]'::jsonb,
        'total', 3
    ),
    'Should return invitation requests with pending requests first'
);

-- Should return paginated invitation requests when limit and offset are provided
select is(
    search_event_invitation_requests(
        :'groupID'::uuid,
        jsonb_build_object('event_id', :'event1ID'::uuid, 'limit', 1, 'offset', 1)
    )::jsonb,
    jsonb_build_object(
        'invitation_requests', '[
            {"created_at": 1704067200, "invitation_request_status": "accepted", "user_id": "3a2f0000-0000-0000-0000-000000000009", "username": "alice", "company": "Cloud Corp", "name": "Alice", "photo_url": "https://example.com/alice.png", "reviewed_at": 1704070800, "title": "Principal Engineer"}
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
        jsonb_build_object('event_id', :'missingEventID'::uuid, 'limit', 50, 'offset', 0)
    )::jsonb,
    jsonb_build_object(
        'invitation_requests', '[]'::jsonb,
        'total', 0
    ),
    'Should return empty list for non-existing event'
);

-- Should return empty list when event belongs to another group
select is(
    search_event_invitation_requests(
        :'group2ID'::uuid,
        jsonb_build_object('event_id', :'event1ID'::uuid, 'limit', 50, 'offset', 0)
    )::jsonb,
    jsonb_build_object(
        'invitation_requests', '[]'::jsonb,
        'total', 0
    ),
    'Should return empty list when event belongs to another group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
