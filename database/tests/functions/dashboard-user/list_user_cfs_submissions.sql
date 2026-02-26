-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set eventCategoryID '00000000-0000-0000-0000-000000000041'
\set eventID '00000000-0000-0000-0000-000000000051'
\set groupCategoryID '00000000-0000-0000-0000-000000000021'
\set groupID '00000000-0000-0000-0000-000000000031'
\set label1ID '00000000-0000-0000-0000-000000000101'
\set label2ID '00000000-0000-0000-0000-000000000102'
\set proposal1ID '00000000-0000-0000-0000-000000000061'
\set proposal2ID '00000000-0000-0000-0000-000000000062'
\set submission1ID '00000000-0000-0000-0000-000000000071'
\set submission2ID '00000000-0000-0000-0000-000000000072'
\set userEmptyID '00000000-0000-0000-0000-000000000099'
\set userID '00000000-0000-0000-0000-000000000081'

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
insert into event_category (event_category_id, community_id, name) values
    (:'eventCategoryID', :'communityID', 'Meetup');

-- User
insert into "user" (user_id, auth_hash, email, username, email_verified, name) values
    (:'userID', gen_random_bytes(32), 'alice@example.com', 'alice', true, 'Alice');

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
        :'userID'
    ),
    (
        :'proposal2ID',
        '2024-01-03 00:00:00+00',
        'Talk about Go',
        make_interval(mins => 60),
        'intermediate',
        'Go Intro',
        :'userID'
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

-- Event CFS labels
insert into event_cfs_label (event_cfs_label_id, event_id, name, color) values
    (:'label1ID', :'eventID', 'track / backend', '#DBEAFE'),
    (:'label2ID', :'eventID', 'track / frontend', '#FEE2E2');

-- CFS submissions
insert into cfs_submission (
    cfs_submission_id,
    created_at,
    event_id,
    session_proposal_id,
    status_id,
    action_required_message
) values
    (
        :'submission1ID',
        '2024-01-04 00:00:00+00',
        :'eventID',
        :'proposal1ID',
        'information-requested',
        'Need more info'
    ),
    (
        :'submission2ID',
        '2024-01-03 00:00:00+00',
        :'eventID',
        :'proposal2ID',
        'not-reviewed',
        null
    );

-- CFS submission labels
insert into cfs_submission_label (cfs_submission_id, event_cfs_label_id) values
    (:'submission1ID', :'label1ID'),
    (:'submission2ID', :'label1ID'),
    (:'submission2ID', :'label2ID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should list user submissions
select is(
    list_user_cfs_submissions(:'userID'::uuid, '{"limit": 10, "offset": 0}'::jsonb)::jsonb,
    jsonb_build_object(
        'submissions',
        jsonb_build_array(
            jsonb_build_object(
                'action_required_message',
                'Need more info',
                'cfs_submission_id',
                :'submission1ID'::uuid,
                'created_at',
                extract(epoch from '2024-01-04 00:00:00+00'::timestamptz)::bigint,
                'event',
                get_event_summary(:'communityID'::uuid, :'groupID'::uuid, :'eventID'::uuid)::jsonb,
                'labels',
                jsonb_build_array(
                    jsonb_build_object(
                        'color',
                        '#DBEAFE',
                        'event_cfs_label_id',
                        :'label1ID'::uuid,
                        'name',
                        'track / backend'
                    )
                ),
                'linked_session_id',
                null,
                'session_proposal',
                jsonb_build_object(
                    'description',
                    'Talk about Rust',
                    'duration_minutes',
                    45,
                    'session_proposal_id',
                    :'proposal1ID'::uuid,
                    'session_proposal_level_id',
                    'beginner',
                    'session_proposal_level_name',
                    'Beginner',
                    'title',
                    'Rust Intro'
                ),
                'status_id',
                'information-requested',
                'status_name',
                'Information requested',
                'updated_at',
                null
            ),
            jsonb_build_object(
                'action_required_message',
                null,
                'cfs_submission_id',
                :'submission2ID'::uuid,
                'created_at',
                extract(epoch from '2024-01-03 00:00:00+00'::timestamptz)::bigint,
                'event',
                get_event_summary(:'communityID'::uuid, :'groupID'::uuid, :'eventID'::uuid)::jsonb,
                'labels',
                jsonb_build_array(
                    jsonb_build_object(
                        'color',
                        '#DBEAFE',
                        'event_cfs_label_id',
                        :'label1ID'::uuid,
                        'name',
                        'track / backend'
                    ),
                    jsonb_build_object(
                        'color',
                        '#FEE2E2',
                        'event_cfs_label_id',
                        :'label2ID'::uuid,
                        'name',
                        'track / frontend'
                    )
                ),
                'linked_session_id',
                null,
                'session_proposal',
                jsonb_build_object(
                    'description',
                    'Talk about Go',
                    'duration_minutes',
                    60,
                    'session_proposal_id',
                    :'proposal2ID'::uuid,
                    'session_proposal_level_id',
                    'intermediate',
                    'session_proposal_level_name',
                    'Intermediate',
                    'title',
                    'Go Intro'
                ),
                'status_id',
                'not-reviewed',
                'status_name',
                'Not reviewed',
                'updated_at',
                null
            )
        ),
        'total',
        2
    ),
    'Should list user submissions'
);

-- Should paginate submissions
select is(
    list_user_cfs_submissions(:'userID'::uuid, '{"limit": 1, "offset": 1}'::jsonb)::jsonb,
    jsonb_build_object(
        'submissions',
        jsonb_build_array(
            jsonb_build_object(
                'action_required_message',
                null,
                'cfs_submission_id',
                :'submission2ID'::uuid,
                'created_at',
                extract(epoch from '2024-01-03 00:00:00+00'::timestamptz)::bigint,
                'event',
                get_event_summary(:'communityID'::uuid, :'groupID'::uuid, :'eventID'::uuid)::jsonb,
                'labels',
                jsonb_build_array(
                    jsonb_build_object(
                        'color',
                        '#DBEAFE',
                        'event_cfs_label_id',
                        :'label1ID'::uuid,
                        'name',
                        'track / backend'
                    ),
                    jsonb_build_object(
                        'color',
                        '#FEE2E2',
                        'event_cfs_label_id',
                        :'label2ID'::uuid,
                        'name',
                        'track / frontend'
                    )
                ),
                'linked_session_id',
                null,
                'session_proposal',
                jsonb_build_object(
                    'description',
                    'Talk about Go',
                    'duration_minutes',
                    60,
                    'session_proposal_id',
                    :'proposal2ID'::uuid,
                    'session_proposal_level_id',
                    'intermediate',
                    'session_proposal_level_name',
                    'Intermediate',
                    'title',
                    'Go Intro'
                ),
                'status_id',
                'not-reviewed',
                'status_name',
                'Not reviewed',
                'updated_at',
                null
            )
        ),
        'total',
        2
    ),
    'Should paginate submissions'
);

-- Should return empty submissions for users without submissions
select is(
    list_user_cfs_submissions(:'userEmptyID'::uuid, '{"limit": 10, "offset": 0}'::jsonb)::jsonb,
    jsonb_build_object(
        'submissions', '[]'::jsonb,
        'total', 0
    ),
    'Should return empty submissions for users without submissions'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
