-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '4a140000-0000-0000-0000-000000000001'
\set eventCategoryID '4a140000-0000-0000-0000-000000000002'
\set eventID '4a140000-0000-0000-0000-000000000003'
\set groupCategoryID '4a140000-0000-0000-0000-000000000004'
\set groupID '4a140000-0000-0000-0000-000000000005'
\set proposal1ID '4a140000-0000-0000-0000-000000000006'
\set proposal2ID '4a140000-0000-0000-0000-000000000007'
\set proposal3ID '4a140000-0000-0000-0000-000000000008'
\set proposal4ID '4a140000-0000-0000-0000-000000000009'
\set sessionID '4a140000-0000-0000-0000-000000000010'
\set submission1ID '4a140000-0000-0000-0000-000000000011'
\set submission2ID '4a140000-0000-0000-0000-000000000012'
\set submission3ID '4a140000-0000-0000-0000-000000000013'
\set submission4ID '4a140000-0000-0000-0000-000000000014'
\set user1ID '4a140000-0000-0000-0000-000000000015'
\set user2ID '4a140000-0000-0000-0000-000000000016'

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
    'cfs-resubmit-community',
    'CFS Resubmit Community',
    'Community for testing CFS resubmission',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

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
);

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'CFS Resubmit Group', 'cfs-resubmit');

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
        'Talk about Rust',
        make_interval(mins => 45),
        'beginner',
        'Rust Intro',
        :'user1ID'
    ),
    (
        :'proposal2ID',
        '2024-01-03 00:00:00+00',
        'Talk about Go',
        make_interval(mins => 60),
        'intermediate',
        'Go Intro',
        :'user1ID'
    ),
    (
        :'proposal3ID',
        '2024-01-04 00:00:00+00',
        'Talk about Python',
        make_interval(mins => 30),
        'beginner',
        'Python Intro',
        :'user2ID'
    ),
    (
        :'proposal4ID',
        '2024-01-05 00:00:00+00',
        'Talk about Databases',
        make_interval(mins => 45),
        'intermediate',
        'Database Intro',
        :'user1ID'
    );

-- Event
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    published,
    cfs_description,
    cfs_enabled,
    cfs_starts_at,
    cfs_ends_at,
    starts_at,
    ends_at
) values (
    :'eventID',
    :'groupID',
    'Event 1',
    'event-1',
    'Event description',
    'UTC',
    :'eventCategoryID',
    'in-person',
    true,
    'CFS open',
    true,
    current_timestamp - interval '1 day',
    current_timestamp + interval '1 day',
    current_timestamp + interval '7 days',
    current_timestamp + interval '8 days'
);

-- CFS submissions
insert into cfs_submission (
    cfs_submission_id,
    event_id,
    session_proposal_id,
    status_id,
    action_required_message
) values
    (
        :'submission1ID',
        :'eventID',
        :'proposal1ID',
        'information-requested',
        'Need more info'
    ),
    (
        :'submission2ID',
        :'eventID',
        :'proposal2ID',
        'approved',
        null
    ),
    (
        :'submission3ID',
        :'eventID',
        :'proposal3ID',
        'information-requested',
        'Need more info'
    ),
    (
        :'submission4ID',
        :'eventID',
        :'proposal4ID',
        'approved',
        null
    );

-- Linked session
insert into session (
    session_id,
    cfs_submission_id,
    event_id,
    name,
    session_kind_id,
    starts_at
) values (
    :'sessionID',
    :'submission4ID',
    :'eventID',
    'Linked Session',
    'in-person',
    current_timestamp + interval '7 days'
);

-- Linked submission guard state
update cfs_submission
set
    action_required_message = 'Need final info',
    status_id = 'information-requested'
where cfs_submission_id = :'submission4ID'::uuid;

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject resubmitting another user's submission
select throws_ok(
    format(
        'select resubmit_cfs_submission(%L::uuid, %L::uuid)',
        :'user1ID',
        :'submission3ID'
    ),
    'submission not found or cannot be resubmitted',
    'Should reject resubmitting another user''s submission'
);

-- Resubmit submission
select lives_ok(
    format(
        $$
            select resubmit_cfs_submission(%L::uuid, %L::uuid)
        $$,
        :'user1ID',
        :'submission1ID'
    ),
    'Should execute resubmit_cfs_submission successfully'
);

-- Should resubmit submission
select is(
    (select status_id from cfs_submission where cfs_submission_id = :'submission1ID'::uuid),
    'not-reviewed',
    'Should reset submission status to not-reviewed'
);

-- Should clear action required message
select is(
    (select action_required_message from cfs_submission where cfs_submission_id = :'submission1ID'::uuid),
    null,
    'Should clear action required message'
);

-- Should create the expected audit row
select results_eq(
    $$
        select
            action,
            actor_user_id,
            actor_username,
            resource_type,
            resource_id
        from audit_log
    $$,
    format(
        $$
            values (
                'submission_resubmitted',
                %L::uuid,
                'alice',
                'cfs_submission',
                %L::uuid
            )
        $$,
        :'user1ID',
        :'submission1ID'
    ),
    'Should create the expected audit row'
);

-- Should reject resubmitting approved submission
select throws_ok(
    format(
        'select resubmit_cfs_submission(%L::uuid, %L::uuid)',
        :'user1ID',
        :'submission2ID'
    ),
    'submission not found or cannot be resubmitted',
    'Should reject resubmitting approved submission'
);

-- Should reject resubmitting submission linked to a session
select throws_ok(
    format(
        'select resubmit_cfs_submission(%L::uuid, %L::uuid)',
        :'user1ID',
        :'submission4ID'
    ),
    'submission not found or cannot be resubmitted',
    'Should reject resubmitting submission linked to a session'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
