-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '79300000-0000-0000-0000-000000000001'
\set confirmedUserID '79300000-0000-0000-0000-000000000008'
\set eventCategoryID '79300000-0000-0000-0000-000000000003'
\set eventID '79300000-0000-0000-0000-000000000005'
\set groupCategoryID '79300000-0000-0000-0000-000000000002'
\set groupID '79300000-0000-0000-0000-000000000004'
\set noQuestionsUserID '79300000-0000-0000-0000-000000000006'
\set pendingUserID '79300000-0000-0000-0000-000000000007'
\set registrationQuestionID '79300000-0000-0000-0000-000000000101'

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
    'pending-answers-alliance',
    'Pending Answers Alliance',
    'Test',
    'https://e/banner-mobile.png',
    'https://e/banner.png',
    'https://e/logo.png'
);

-- Group category
insert into group_category (group_category_id, alliance_id, name)
values (:'groupCategoryID', :'allianceID', 'Tech');

-- Event category
insert into event_category (event_category_id, alliance_id, name)
values (:'eventCategoryID', :'allianceID', 'General');

-- Users
insert into "user" (user_id, auth_hash, email, email_verified, username)
values
    (
        :'confirmedUserID',
        'hash-3',
        'confirmed@example.com',
        true,
        'confirmed-user'
    ),
    (
        :'noQuestionsUserID',
        'hash-1',
        'no-questions@example.com',
        true,
        'no-questions-user'
    ),
    (
        :'pendingUserID',
        'hash-2',
        'pending@example.com',
        true,
        'pending-user'
    );

-- Group
insert into "group" (group_id, alliance_id, group_category_id, name, slug)
values (
    :'groupID',
    :'allianceID',
    :'groupCategoryID',
    'Pending Answers Group',
    'pending-answers-group'
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
    jsonb_build_object(
        'answers',
        jsonb_build_array(jsonb_build_object(
            'question_id', :'registrationQuestionID',
            'value', 'Original'
        ))
    ),
    'confirmed'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should ignore events without registration questions
select lives_ok(
    format($$
        select upsert_pending_registration_answers(
            %L::uuid,
            %L::uuid,
            '[]'::jsonb,
            '{"answers": [{"question_id": "%s", "value": "Ignored"}]}'::jsonb
        )
    $$, :'eventID', :'noQuestionsUserID', :'registrationQuestionID'),
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
    format($$
        select upsert_pending_registration_answers(
            %L::uuid,
            %L::uuid,
            '[{"id": "%s", "kind": "free-text", "prompt": "Note", "required": true, "options": []}]'::jsonb,
            null
        )
    $$, :'eventID', :'pendingUserID', :'registrationQuestionID'),
    'questionnaire answers are required',
    'Should validate answers before writing the attendee row'
);

-- Should insert a new pending attendee row with answers
select lives_ok(
    format($$
        select upsert_pending_registration_answers(
            %L::uuid,
            %L::uuid,
            '[{"id": "%s", "kind": "free-text", "prompt": "Note", "required": true, "options": []}]'::jsonb,
            '{"answers": [{"question_id": "%s", "value": "Initial"}]}'::jsonb
        )
    $$, :'eventID', :'pendingUserID', :'registrationQuestionID', :'registrationQuestionID'),
    'Should insert a new pending attendee row with answers'
);

select results_eq(
    format($$
        select status, registration_answers
        from event_attendee
        where event_id = %L::uuid
        and user_id = %L::uuid
    $$, :'eventID', :'pendingUserID'),
    format(
        $$ values ('registration-questions-pending'::text, '{"answers": [{"question_id": "%s", "value": "Initial"}]}'::jsonb) $$,
        :'registrationQuestionID'
    ),
    'Should store the pending registration answers'
);

-- Should refresh answers for an existing pending attendee row
select lives_ok(
    format($$
        select upsert_pending_registration_answers(
            %L::uuid,
            %L::uuid,
            '[{"id": "%s", "kind": "free-text", "prompt": "Note", "required": true, "options": []}]'::jsonb,
            '{"answers": [{"question_id": "%s", "value": "Updated"}]}'::jsonb
        )
    $$, :'eventID', :'pendingUserID', :'registrationQuestionID', :'registrationQuestionID'),
    'Should refresh answers for an existing pending attendee row'
);

select is(
    (
        select registration_answers
        from event_attendee
        where event_id = :'eventID'::uuid
        and user_id = :'pendingUserID'::uuid
    ),
    format(
        $${"answers": [{"question_id": "%s", "value": "Updated"}]}$$,
        :'registrationQuestionID'
    )::jsonb,
    'Should update the existing pending attendee answers'
);

-- Should leave confirmed attendees untouched on conflict
select lives_ok(
    format($$
        select upsert_pending_registration_answers(
            %L::uuid,
            %L::uuid,
            '[{"id": "%s", "kind": "free-text", "prompt": "Note", "required": true, "options": []}]'::jsonb,
            '{"answers": [{"question_id": "%s", "value": "Ignored"}]}'::jsonb
        )
    $$, :'eventID', :'confirmedUserID', :'registrationQuestionID', :'registrationQuestionID'),
    'Should leave confirmed attendees untouched on conflict'
);

select results_eq(
    format($$
        select status, registration_answers
        from event_attendee
        where event_id = %L::uuid
        and user_id = %L::uuid
    $$, :'eventID', :'confirmedUserID'),
    format(
        $$ values ('confirmed'::text, '{"answers": [{"question_id": "%s", "value": "Original"}]}'::jsonb) $$,
        :'registrationQuestionID'
    ),
    'Should keep confirmed attendee status and answers unchanged'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
