-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(12);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3a2f0000-0000-0000-0000-000000000001'
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

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'communityID',
    'invitation-search-community',
    'Invitation Search Community',
    'A test community for invitation search',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Tech');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'General');

-- Groups
insert into "group" (group_id, community_id, group_category_id, name, slug)
values
    (:'groupID', :'communityID', :'groupCategoryID', 'Invitation Group', 'invitation-group'),
    (:'group2ID', :'communityID', :'groupCategoryID', 'Other Group', 'other-group');

-- Users
insert into "user" (
    auth_hash,
    bio,
    email,
    github_url,
    provider,
    user_id,
    username,
    website_url,

    company,
    name,
    photo_url,
    title
) values (
    gen_random_bytes(32),
    'Reviews invitation requests',
    'alice@example.com',
    'https://github.com/alice',
    '{"github": {"username": "alice-gh", "private": "secret"}, "linuxfoundation": {"username": "alice-lf", "subject": "secret"}}'::jsonb,
    :'user1ID',
    'alice',
    'https://example.com/alice',
    'Cloud Corp',
    'Alice',
    'https://example.com/alice.png',
    'Principal Engineer'
), (
    gen_random_bytes(32),
    null,
    'bob@example.com',
    null,
    null,
    :'user2ID',
    'bob',
    null,
    null,
    null,
    'https://example.com/bob.png',
    null
), (
    gen_random_bytes(32),
    null,
    'carol@example.com',
    null,
    null,
    :'user3ID',
    'carol',
    null,
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

-- Should return invitation requests by requested date descending by default
select is(
    search_event_invitation_requests(
        :'groupID'::uuid,
        :'event1ID'::uuid,
        jsonb_build_object('limit', 50, 'offset', 0)
    )::jsonb,
    jsonb_build_object(
        'invitation_requests', '[
            {"created_at": 1704240000, "invitation_request_status": "rejected", "user": {"user_id": "3a2f0000-0000-0000-0000-000000000011", "username": "carol", "name": "Carol", "title": "Designer"}, "reviewed_at": 1704243600},
            {"created_at": 1704153600, "invitation_request_status": "pending", "user": {"user_id": "3a2f0000-0000-0000-0000-000000000010", "username": "bob", "photo_url": "https://example.com/bob.png"}, "reviewed_at": null},
            {"created_at": 1704067200, "invitation_request_status": "accepted", "user": {"user_id": "3a2f0000-0000-0000-0000-000000000009", "username": "alice", "bio": "Reviews invitation requests", "company": "Cloud Corp", "github_url": "https://github.com/alice", "name": "Alice", "photo_url": "https://example.com/alice.png", "provider": {"github": {"username": "alice-gh"}, "linuxfoundation": {"username": "alice-lf"}}, "title": "Principal Engineer", "website_url": "https://example.com/alice"}, "reviewed_at": 1704070800}
        ]'::jsonb,
        'total', 3
    ),
    'Should return invitation requests by requested date descending by default'
);

-- Should return paginated invitation requests when limit and offset are provided
select is(
    search_event_invitation_requests(
        :'groupID'::uuid,
        :'event1ID'::uuid,
        jsonb_build_object('limit', 1, 'offset', 1)
    )::jsonb,
    jsonb_build_object(
        'invitation_requests', '[
            {"created_at": 1704153600, "invitation_request_status": "pending", "user": {"user_id": "3a2f0000-0000-0000-0000-000000000010", "username": "bob", "photo_url": "https://example.com/bob.png"}, "reviewed_at": null}
        ]'::jsonb,
        'total', 3
    ),
    'Should return paginated invitation requests when limit and offset are provided'
);

-- Should return empty list when event scope is null
select is(
    search_event_invitation_requests(
        :'groupID'::uuid,
        null::uuid,
        '{"limit":50,"offset":0}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'invitation_requests', '[]'::jsonb,
        'total', 0
    ),
    'Should return empty list when event scope is null'
);

-- Should return empty list for non-existing event
select is(
    search_event_invitation_requests(
        :'groupID'::uuid,
        :'missingEventID'::uuid,
        jsonb_build_object('limit', 50, 'offset', 0)
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
        :'event1ID'::uuid,
        jsonb_build_object('limit', 50, 'offset', 0)
    )::jsonb,
    jsonb_build_object(
        'invitation_requests', '[]'::jsonb,
        'total', 0
    ),
    'Should return empty list when event belongs to another group'
);

-- Should filter invitation requests by identity search query
select ok(
    (
        with result as (
            select search_event_invitation_requests(
                :'groupID'::uuid,
                :'event1ID'::uuid,
                jsonb_build_object(
                    'limit', 50,
                    'offset', 0,
                    'ts_query', 'ali'
                )
            )::jsonb as data
        )
        select (data->>'total')::int = 1
        and data#>>'{invitation_requests,0,user,user_id}' = :'user1ID'
        from result
    ),
    'Should filter invitation requests by identity search query'
);

-- Should filter invitation requests by company search query
select ok(
    (
        with result as (
            select search_event_invitation_requests(
                :'groupID'::uuid,
                :'event1ID'::uuid,
                jsonb_build_object(
                    'limit', 50,
                    'offset', 0,
                    'ts_query', 'cloud corp'
                )
            )::jsonb as data
        )
        select (data->>'total')::int = 1
        and data#>>'{invitation_requests,0,user,user_id}' = :'user1ID'
        from result
    ),
    'Should filter invitation requests by company search query'
);

-- Should filter invitation requests by title search query
select ok(
    (
        with result as (
            select search_event_invitation_requests(
                :'groupID'::uuid,
                :'event1ID'::uuid,
                jsonb_build_object(
                    'limit', 50,
                    'offset', 0,
                    'ts_query', 'designer'
                )
            )::jsonb as data
        )
        select (data->>'total')::int = 1
        and data#>>'{invitation_requests,0,user,user_id}' = :'user3ID'
        from result
    ),
    'Should filter invitation requests by title search query'
);

-- Should sort invitation requests by requester name ascending
select is(
    search_event_invitation_requests(
        :'groupID'::uuid,
        :'event1ID'::uuid,
        jsonb_build_object(
            'limit', 50,
            'offset', 0,
            'sort', 'name-asc'
        )
    )::jsonb#>>'{invitation_requests,0,user,username}',
    'alice',
    'Should sort invitation requests by requester name ascending'
);

-- Should filter invitation requests by status
select is(
    search_event_invitation_requests(
        :'groupID'::uuid,
        :'event1ID'::uuid,
        jsonb_build_object(
            'limit', 50,
            'offset', 0,
            'status', 'pending'
        )
    )::jsonb->>'total',
    '1',
    'Should filter invitation requests by status'
);

-- Should filter invitation requests by title presence
select is(
    search_event_invitation_requests(
        :'groupID'::uuid,
        :'event1ID'::uuid,
        jsonb_build_object(
            'limit', 50,
            'offset', 0,
            'title', 'present'
        )
    )::jsonb->>'total',
    '2',
    'Should filter invitation requests by title presence'
);

-- Should return no invitation requests when search has no matches
select is(
    search_event_invitation_requests(
        :'groupID'::uuid,
        :'event1ID'::uuid,
        jsonb_build_object(
            'limit', 50,
            'offset', 0,
            'ts_query', 'missing person'
        )
    )::jsonb,
    jsonb_build_object(
        'invitation_requests', '[]'::jsonb,
        'total', 0
    ),
    'Should return no invitation requests when search has no matches'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
