-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set eventCategoryID '00000000-0000-0000-0000-000000000041'
\set eventID '00000000-0000-0000-0000-000000000051'
\set eventClosedID '00000000-0000-0000-0000-000000000052'
\set eventDisabledID '00000000-0000-0000-0000-000000000053'
\set eventUnpublishedID '00000000-0000-0000-0000-000000000054'
\set groupCategoryID '00000000-0000-0000-0000-000000000021'
\set groupID '00000000-0000-0000-0000-000000000031'
\set proposalID '00000000-0000-0000-0000-000000000061'
\set userID '00000000-0000-0000-0000-000000000071'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url) values
    (:'communityID', 'c1', 'C1', 'd', 'https://e/logo.png', 'https://e/banner_mobile.png', 'https://e/banner.png');

-- Group category
insert into group_category (group_category_id, community_id, name) values
    (:'groupCategoryID', :'communityID', 'Tech');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug) values
    (:'groupID', :'communityID', :'groupCategoryID', 'G1', 'g1');

-- Event category
insert into event_category (event_category_id, community_id, name, slug) values
    (:'eventCategoryID', :'communityID', 'Meetup', 'meetup');

-- User
insert into "user" (user_id, auth_hash, email, username, email_verified, name) values
    (:'userID', gen_random_bytes(32), 'alice@example.com', 'alice', true, 'Alice');

-- Session proposal
insert into session_proposal (
    session_proposal_id,
    created_at,
    description,
    duration,
    session_proposal_level_id,
    title,
    user_id
) values (
    :'proposalID',
    '2024-01-02 00:00:00+00',
    'Talk about Rust',
    make_interval(mins => 45),
    'beginner',
    'Rust Intro',
    :'userID'
);

-- Event (open)
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

-- Event (closed)
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
    :'eventClosedID',
    :'groupID',
    'Event Closed',
    'event-closed',
    'Event description',
    'UTC',
    :'eventCategoryID',
    'in-person',
    true,
    'CFS closed',
    true,
    current_timestamp + interval '2 days',
    current_timestamp + interval '3 days',
    current_timestamp + interval '10 days',
    current_timestamp + interval '11 days'
);

-- Event (CFS disabled)
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
    :'eventDisabledID',
    :'groupID',
    'Event Disabled',
    'event-disabled',
    'Event description',
    'UTC',
    :'eventCategoryID',
    'in-person',
    true,
    null,
    false,
    null,
    null,
    current_timestamp + interval '7 days',
    current_timestamp + interval '8 days'
);

-- Event (unpublished)
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
    :'eventUnpublishedID',
    :'groupID',
    'Event Unpublished',
    'event-unpublished',
    'Event description',
    'UTC',
    :'eventCategoryID',
    'in-person',
    false,
    'CFS open',
    true,
    current_timestamp - interval '1 day',
    current_timestamp + interval '1 day',
    current_timestamp + interval '7 days',
    current_timestamp + interval '8 days'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject submissions when CFS is closed
select throws_ok(
    format(
        'select add_cfs_submission(%L::uuid, %L::uuid, %L::uuid)',
        :'userID',
        :'eventClosedID',
        :'proposalID'
    ),
    'cfs is not open',
    'Should reject submissions when CFS is closed'
);

-- Should reject submissions when CFS is disabled
select throws_ok(
    format(
        'select add_cfs_submission(%L::uuid, %L::uuid, %L::uuid)',
        :'userID',
        :'eventDisabledID',
        :'proposalID'
    ),
    'cfs is not enabled for this event',
    'Should reject submissions when CFS is disabled'
);

-- Should reject submissions when event is unpublished
select throws_ok(
    format(
        'select add_cfs_submission(%L::uuid, %L::uuid, %L::uuid)',
        :'userID',
        :'eventUnpublishedID',
        :'proposalID'
    ),
    'cfs is not enabled for this event',
    'Should reject submissions when event is unpublished'
);

-- Add CFS submission
select add_cfs_submission(:'userID'::uuid, :'eventID'::uuid, :'proposalID'::uuid) as submission_id \gset

-- Should add CFS submission
select is(
    (select count(*) from cfs_submission where cfs_submission_id = :'submission_id'::uuid),
    1::bigint,
    'Should add CFS submission'
);

-- Should reject duplicate CFS submissions
select throws_ok(
    format(
        'select add_cfs_submission(%L::uuid, %L::uuid, %L::uuid)',
        :'userID',
        :'eventID',
        :'proposalID'
    ),
    '23505',
    null,
    'Should reject duplicate CFS submissions'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
