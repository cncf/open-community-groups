-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3a170000-0000-0000-0000-000000000001'
\set eventCategoryID '3a170000-0000-0000-0000-000000000002'
\set eventID '3a170000-0000-0000-0000-000000000003'
\set eventNoApprovedID '3a170000-0000-0000-0000-000000000004'
\set groupCategoryID '3a170000-0000-0000-0000-000000000005'
\set groupID '3a170000-0000-0000-0000-000000000006'
\set proposal1ID '3a170000-0000-0000-0000-000000000007'
\set proposal2ID '3a170000-0000-0000-0000-000000000008'
\set proposal3ID '3a170000-0000-0000-0000-000000000009'
\set submission1ID '3a170000-0000-0000-0000-000000000010'
\set submission2ID '3a170000-0000-0000-0000-000000000011'
\set submission3ID '3a170000-0000-0000-0000-000000000012'
\set submission4ID '3a170000-0000-0000-0000-000000000013'
\set submission5ID '3a170000-0000-0000-0000-000000000014'
\set user1ID '3a170000-0000-0000-0000-000000000015'
\set user2ID '3a170000-0000-0000-0000-000000000016'
\set user3ID '3a170000-0000-0000-0000-000000000017'

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
    'test-community',
    'Test Community',
    'A test community',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Tech');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'Meetup');

-- Users
insert into "user" (
    user_id,
    auth_hash,
    email,
    email_verified,
    username,
    name
) values (
    :'user1ID',
    gen_random_bytes(32),
    'alice@example.com',
    true,
    'alice',
    'Alice'
), (
    :'user2ID',
    gen_random_bytes(32),
    'bob@example.com',
    true,
    'bob',
    'Bob'
), (
    :'user3ID',
    gen_random_bytes(32),
    'carol@example.com',
    true,
    'carol',
    'Carol'
);

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Test Group', 'test-group');

-- Session proposals
insert into session_proposal (
    session_proposal_id,
    created_at,
    description,
    duration,
    session_proposal_level_id,
    title,
    user_id
) values
    (
        :'proposal1ID',
        '2024-01-02 00:00:00+00',
        'Alpha talk',
        make_interval(mins => 45),
        'beginner',
        'Alpha Talk',
        :'user1ID'
    ),
    (
        :'proposal2ID',
        '2024-01-03 00:00:00+00',
        'Beta talk',
        make_interval(mins => 60),
        'intermediate',
        'Beta Talk',
        :'user2ID'
    ),
    (
        :'proposal3ID',
        '2024-01-04 00:00:00+00',
        'Gamma talk',
        make_interval(mins => 30),
        'advanced',
        'Gamma Talk',
        :'user3ID'
    );

-- Event
insert into event (
    event_id,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    published
) values (
    :'eventID',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Event 1',
    'event-1',
    'Event description',
    'UTC',
    true
);

insert into event (
    event_id,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    published
) values (
    :'eventNoApprovedID',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Event 2',
    'event-2',
    'Event description',
    'UTC',
    true
);

-- CFS submissions
insert into cfs_submission (
    cfs_submission_id,
    event_id,
    session_proposal_id,
    status_id
) values
    (:'submission1ID', :'eventID', :'proposal1ID', 'approved'),
    (:'submission2ID', :'eventID', :'proposal2ID', 'approved'),
    (:'submission3ID', :'eventID', :'proposal3ID', 'rejected'),
    (:'submission4ID', :'eventNoApprovedID', :'proposal1ID', 'not-reviewed'),
    (:'submission5ID', :'eventNoApprovedID', :'proposal2ID', 'rejected');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should list approved submissions for sessions
select is(
    list_event_approved_cfs_submissions(:'eventID'::uuid)::jsonb,
    jsonb_build_array(
        jsonb_build_object(
            'cfs_submission_id', :'submission1ID'::uuid,
            'session_proposal_id', :'proposal1ID'::uuid,
            'speaker_name', 'Alice',
            'title', 'Alpha Talk'
        ),
        jsonb_build_object(
            'cfs_submission_id', :'submission2ID'::uuid,
            'session_proposal_id', :'proposal2ID'::uuid,
            'speaker_name', 'Bob',
            'title', 'Beta Talk'
        )
    ),
    'Should list approved submissions for sessions'
);

-- Should return empty list when no submissions are approved
select is(
    list_event_approved_cfs_submissions(:'eventNoApprovedID'::uuid)::jsonb,
    '[]'::jsonb,
    'Should return empty list when no submissions are approved'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
