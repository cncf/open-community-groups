-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '4a170000-0000-0000-0000-000000000001'
\set eventCategoryID '4a170000-0000-0000-0000-000000000002'
\set eventID '4a170000-0000-0000-0000-000000000003'
\set groupCategoryID '4a170000-0000-0000-0000-000000000004'
\set groupID '4a170000-0000-0000-0000-000000000005'
\set proposal1ID '4a170000-0000-0000-0000-000000000006'
\set proposal2ID '4a170000-0000-0000-0000-000000000007'
\set submission1ID '4a170000-0000-0000-0000-000000000008'
\set submission2ID '4a170000-0000-0000-0000-000000000009'
\set user1ID '4a170000-0000-0000-0000-000000000010'
\set user2ID '4a170000-0000-0000-0000-000000000011'

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
    'cfs-withdraw-alliance',
    'CFS Withdraw Alliance',
    'Alliance for testing CFS withdrawal',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, alliance_id, name)
values (:'groupCategoryID', :'allianceID', 'Technology');

-- Event category
insert into event_category (event_category_id, alliance_id, name)
values (:'eventCategoryID', :'allianceID', 'Meetup');

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
insert into "group" (group_id, alliance_id, group_category_id, name, slug)
values (:'groupID', :'allianceID', :'groupCategoryID', 'CFS Withdraw Group', 'cfs-withdraw');

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
    status_id
) values
    (:'submission1ID', :'eventID', :'proposal1ID', 'not-reviewed'),
    (:'submission2ID', :'eventID', :'proposal2ID', 'approved');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject withdrawing another user's submission
select throws_ok(
    format(
        'select withdraw_cfs_submission(%L::uuid, %L::uuid)',
        :'user2ID',
        :'submission1ID'
    ),
    'submission not found or cannot be withdrawn',
    'Should reject withdrawing another user''s submission'
);

-- Withdraw submission
select lives_ok(
    format(
        $$
            select withdraw_cfs_submission(%L::uuid, %L::uuid)
        $$,
        :'user1ID',
        :'submission1ID'
    ),
    'Should execute withdraw_cfs_submission successfully'
);

-- Should withdraw submission
select is(
    (select status_id from cfs_submission where cfs_submission_id = :'submission1ID'::uuid),
    'withdrawn',
    'Should set submission status to withdrawn'
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
                'submission_withdrawn',
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

-- Should reject withdrawing approved submission
select throws_ok(
    format(
        'select withdraw_cfs_submission(%L::uuid, %L::uuid)',
        :'user1ID',
        :'submission2ID'
    ),
    'submission not found or cannot be withdrawn',
    'Should reject withdrawing approved submission'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
