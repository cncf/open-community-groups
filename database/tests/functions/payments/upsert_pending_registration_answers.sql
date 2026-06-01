-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '79300000-0000-0000-0000-000000000001'
\set groupCategoryID '79300000-0000-0000-0000-000000000002'
\set eventCategoryID '79300000-0000-0000-0000-000000000003'
\set groupID '79300000-0000-0000-0000-000000000004'
\set eventID '79300000-0000-0000-0000-000000000005'
\set noQuestionsUserID '79300000-0000-0000-0000-000000000006'
\set pendingUserID '79300000-0000-0000-0000-000000000007'
\set confirmedUserID '79300000-0000-0000-0000-000000000008'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'pending-answers-community', 'Pending Answers Community', 'Test', 'https://e/logo.png', 'https://e/banner-mobile.png', 'https://e/banner.png');

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Tech');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'General');

-- Users
insert into "user" (user_id, auth_hash, email, email_verified, username)
values
    (:'noQuestionsUserID', 'hash-1', 'no-questions@example.com', true, 'no-questions-user'),
    (:'pendingUserID', 'hash-2', 'pending@example.com', true, 'pending-user'),
    (:'confirmedUserID', 'hash-3', 'confirmed@example.com', true, 'confirmed-user');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Pending Answers Group', 'pending-answers-group');

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
    starts_at,
    published,
    published_at
) values (
    :'eventID',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Pending Answers Event',
    'pending-answers-event',
    'Test event',
    'UTC',
    now() + interval '1 day',
    true,
    now()
);

-- Existing confirmed attendee that must not be converted back to pending
insert into event_attendee (event_id, user_id, registration_answers, status)
values (
    :'eventID',
    :'confirmedUserID',
    '{"answers": [{"question_id": "79300000-0000-0000-0000-000000000101", "value": "Original"}]}'::jsonb,
    'confirmed'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should ignore events without registration questions
select lives_ok(
    $$
        select upsert_pending_registration_answers(
            '79300000-0000-0000-0000-000000000005'::uuid,
            '79300000-0000-0000-0000-000000000006'::uuid,
            '[]'::jsonb,
            '{"answers": [{"question_id": "79300000-0000-0000-0000-000000000101", "value": "Ignored"}]}'::jsonb
        )
    $$,
    'Should ignore events without registration questions'
);

select is(
    (
        select count(*)::int
        from event_attendee
        where event_id = :'eventID'::uuid
        and user_id = :'noQuestionsUserID'::uuid
    ),
    0,
    'Should not create a pending attendee row when no questions are configured'
);

-- Should validate answers before writing the attendee row
select throws_ok(
    $$
        select upsert_pending_registration_answers(
            '79300000-0000-0000-0000-000000000005'::uuid,
            '79300000-0000-0000-0000-000000000007'::uuid,
            '[{"id": "79300000-0000-0000-0000-000000000101", "kind": "free-text", "prompt": "Note", "required": true, "options": []}]'::jsonb,
            null
        )
    $$,
    'questionnaire answers are required',
    'Should validate answers before writing the attendee row'
);

-- Should insert a new pending attendee row with answers
select lives_ok(
    $$
        select upsert_pending_registration_answers(
            '79300000-0000-0000-0000-000000000005'::uuid,
            '79300000-0000-0000-0000-000000000007'::uuid,
            '[{"id": "79300000-0000-0000-0000-000000000101", "kind": "free-text", "prompt": "Note", "required": true, "options": []}]'::jsonb,
            '{"answers": [{"question_id": "79300000-0000-0000-0000-000000000101", "value": "Initial"}]}'::jsonb
        )
    $$,
    'Should insert a new pending attendee row with answers'
);

select results_eq(
    $$
        select status, registration_answers
        from event_attendee
        where event_id = '79300000-0000-0000-0000-000000000005'::uuid
        and user_id = '79300000-0000-0000-0000-000000000007'::uuid
    $$,
    $$ values ('registration-questions-pending'::text, '{"answers": [{"question_id": "79300000-0000-0000-0000-000000000101", "value": "Initial"}]}'::jsonb) $$,
    'Should store the pending registration answers'
);

-- Should refresh answers for an existing pending attendee row
select lives_ok(
    $$
        select upsert_pending_registration_answers(
            '79300000-0000-0000-0000-000000000005'::uuid,
            '79300000-0000-0000-0000-000000000007'::uuid,
            '[{"id": "79300000-0000-0000-0000-000000000101", "kind": "free-text", "prompt": "Note", "required": true, "options": []}]'::jsonb,
            '{"answers": [{"question_id": "79300000-0000-0000-0000-000000000101", "value": "Updated"}]}'::jsonb
        )
    $$,
    'Should refresh answers for an existing pending attendee row'
);

select is(
    (
        select registration_answers
        from event_attendee
        where event_id = :'eventID'::uuid
        and user_id = :'pendingUserID'::uuid
    ),
    '{"answers": [{"question_id": "79300000-0000-0000-0000-000000000101", "value": "Updated"}]}'::jsonb,
    'Should update the existing pending attendee answers'
);

-- Should leave confirmed attendees untouched on conflict
select lives_ok(
    $$
        select upsert_pending_registration_answers(
            '79300000-0000-0000-0000-000000000005'::uuid,
            '79300000-0000-0000-0000-000000000008'::uuid,
            '[{"id": "79300000-0000-0000-0000-000000000101", "kind": "free-text", "prompt": "Note", "required": true, "options": []}]'::jsonb,
            '{"answers": [{"question_id": "79300000-0000-0000-0000-000000000101", "value": "Ignored"}]}'::jsonb
        )
    $$,
    'Should leave confirmed attendees untouched on conflict'
);

select results_eq(
    $$
        select status, registration_answers
        from event_attendee
        where event_id = '79300000-0000-0000-0000-000000000005'::uuid
        and user_id = '79300000-0000-0000-0000-000000000008'::uuid
    $$,
    $$ values ('confirmed'::text, '{"answers": [{"question_id": "79300000-0000-0000-0000-000000000101", "value": "Original"}]}'::jsonb) $$,
    'Should keep confirmed attendee status and answers unchanged'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
