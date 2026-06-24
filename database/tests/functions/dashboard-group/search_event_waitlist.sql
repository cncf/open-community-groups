-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(10);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3a300000-0000-0000-0000-000000000001'
\set event1ID '3a300000-0000-0000-0000-000000000002'
\set eventCategoryID '3a300000-0000-0000-0000-000000000003'
\set group2ID '3a300000-0000-0000-0000-000000000004'
\set groupCategoryID '3a300000-0000-0000-0000-000000000005'
\set groupID '3a300000-0000-0000-0000-000000000006'
\set missingEventID '3a300000-0000-0000-0000-000000000007'
\set user1ID '3a300000-0000-0000-0000-000000000008'
\set user2ID '3a300000-0000-0000-0000-000000000009'

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
    'waitlist-community',
    'Waitlist Community',
    'A test community for waitlist search',
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
    (:'groupID', :'communityID', :'groupCategoryID', 'Waitlist Group', 'waitlist-group'),
    (:'group2ID', :'communityID', :'groupCategoryID', 'Other Group', 'other-group');

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
);

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
    published,
    canceled,
    deleted,
    capacity,
    waitlist_enabled
) values (
    :'event1ID',
    'Waitlist Event',
    'waitlist-event',
    'An event for waitlist search',
    'UTC',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    true,
    false,
    false,
    1,
    true
);

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
        jsonb_build_object('event_id', :'event1ID'::uuid, 'limit', 50, 'offset', 0)
    )::jsonb,
    jsonb_build_object(
        'waitlist', '[
            {"created_at": 1704067200, "user_id": "3a300000-0000-0000-0000-000000000008", "username": "alice", "waitlist_position": 1, "company": "Cloud Corp", "name": "Alice", "photo_url": "https://example.com/alice.png", "title": "Principal Engineer"},
            {"created_at": 1704153600, "user_id": "3a300000-0000-0000-0000-000000000009", "username": "bob", "waitlist_position": 2, "company": null, "name": null, "photo_url": "https://example.com/bob.png", "title": null}
        ]'::jsonb,
        'total', 2
    ),
    'Should return waitlist entries with expected fields and FIFO order'
);

-- Should return paginated waitlist entries when limit and offset are provided
select is(
    search_event_waitlist(
        :'groupID'::uuid,
        jsonb_build_object('event_id', :'event1ID'::uuid, 'limit', 1, 'offset', 1)
    )::jsonb,
    jsonb_build_object(
        'waitlist', '[
            {"created_at": 1704153600, "user_id": "3a300000-0000-0000-0000-000000000009", "username": "bob", "waitlist_position": 2, "company": null, "name": null, "photo_url": "https://example.com/bob.png", "title": null}
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
        jsonb_build_object('event_id', :'missingEventID'::uuid, 'limit', 50, 'offset', 0)
    )::jsonb,
    jsonb_build_object(
        'waitlist', '[]'::jsonb,
        'total', 0
    ),
    'Should return empty list for non-existing event'
);

-- Should return empty list when event belongs to another group
select is(
    search_event_waitlist(
        :'group2ID'::uuid,
        jsonb_build_object('event_id', :'event1ID'::uuid, 'limit', 50, 'offset', 0)
    )::jsonb,
    jsonb_build_object(
        'waitlist', '[]'::jsonb,
        'total', 0
    ),
    'Should return empty list when event belongs to another group'
);

-- Should filter waitlist entries by identity search query
select ok(
    (
        with result as (
            select search_event_waitlist(
                :'groupID'::uuid,
                jsonb_build_object(
                    'event_id', :'event1ID'::uuid,
                    'limit', 50,
                    'offset', 0,
                    'ts_query', 'ali'
                )
            )::jsonb as data
        )
        select (data->>'total')::int = 1
        and data#>>'{waitlist,0,user_id}' = :'user1ID'
        and data#>>'{waitlist,0,waitlist_position}' = '1'
        from result
    ),
    'Should filter waitlist entries by identity search query'
);

-- Should filter waitlist entries by company search query
select ok(
    (
        with result as (
            select search_event_waitlist(
                :'groupID'::uuid,
                jsonb_build_object(
                    'event_id', :'event1ID'::uuid,
                    'limit', 50,
                    'offset', 0,
                    'ts_query', 'cloud corp'
                )
            )::jsonb as data
        )
        select (data->>'total')::int = 1
        and data#>>'{waitlist,0,user_id}' = :'user1ID'
        and data#>>'{waitlist,0,waitlist_position}' = '1'
        from result
    ),
    'Should filter waitlist entries by company search query'
);

-- Should filter waitlist entries by title search query
select ok(
    (
        with result as (
            select search_event_waitlist(
                :'groupID'::uuid,
                jsonb_build_object(
                    'event_id', :'event1ID'::uuid,
                    'limit', 50,
                    'offset', 0,
                    'ts_query', 'principal engineer'
                )
            )::jsonb as data
        )
        select (data->>'total')::int = 1
        and data#>>'{waitlist,0,user_id}' = :'user1ID'
        and data#>>'{waitlist,0,waitlist_position}' = '1'
        from result
    ),
    'Should filter waitlist entries by title search query'
);

-- Should keep real waitlist position when search filters earlier entries
select ok(
    (
        with result as (
            select search_event_waitlist(
                :'groupID'::uuid,
                jsonb_build_object(
                    'event_id', :'event1ID'::uuid,
                    'limit', 50,
                    'offset', 0,
                    'ts_query', 'bob'
                )
            )::jsonb as data
        )
        select (data->>'total')::int = 1
        and data#>>'{waitlist,0,user_id}' = :'user2ID'
        and data#>>'{waitlist,0,waitlist_position}' = '2'
        from result
    ),
    'Should keep real waitlist position when search filters earlier entries'
);

-- Should return no waitlist entries when search has no matches
select is(
    search_event_waitlist(
        :'groupID'::uuid,
        jsonb_build_object(
            'event_id', :'event1ID'::uuid,
            'limit', 50,
            'offset', 0,
            'ts_query', 'missing person'
        )
    )::jsonb,
    jsonb_build_object(
        'waitlist', '[]'::jsonb,
        'total', 0
    ),
    'Should return no waitlist entries when search has no matches'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
