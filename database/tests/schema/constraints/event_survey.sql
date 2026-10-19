-- Tests event survey constraints.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(18);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set cascadeEventID 'a5e00001-0000-0000-0000-000000000001'
\set cascadeSurveyID 'a5e00001-0000-0000-0000-000000000002'
\set communityID 'a5e00001-0000-0000-0000-000000000003'
\set creatorSurveyID 'a5e00001-0000-0000-0000-000000000004'
\set creatorUserID 'a5e00001-0000-0000-0000-000000000005'
\set eventCategoryID 'a5e00001-0000-0000-0000-000000000006'
\set eventID 'a5e00001-0000-0000-0000-000000000007'
\set groupCategoryID 'a5e00001-0000-0000-0000-000000000008'
\set groupID 'a5e00001-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community hosting the surveyed events
select fx_community(:'communityID');

-- User who creates the survey cleared on user deletion
select fx_user(:'creatorUserID');

-- Event category used by the surveyed events
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category used by the surveyed events group
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group hosting the surveyed events
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event deleted together with its survey
select fx_event(:'cascadeEventID', :'groupID', :'eventCategoryID');

-- Event receiving the surveys written by the constraint scenarios
select fx_event(:'eventID', :'groupID', :'eventCategoryID');

-- Survey deleted through the event cascade
insert into event_survey (event_survey_id, event_id, title)
values (:'cascadeSurveyID', :'cascadeEventID', 'Cascade survey');

-- Survey whose creator is deleted
insert into event_survey (event_survey_id, event_id, title, created_by)
values (:'creatorSurveyID', :'eventID', 'Creator survey', :'creatorUserID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept surveys with every optional setting
select lives_ok(
    format(
        $$
            insert into event_survey (
                anonymous,
                audience,
                event_id,
                questions,
                revision,
                status,
                title,

                closed_at,
                closes_at,
                description,
                first_response_at,
                open_notification_processed_at,
                open_notification_recipients,
                opens_at,
                updated_at
            ) values (
                false,
                'checked-in',
                %L::uuid,
                '[{"id": "a5e00001-0000-0000-0000-000000000010", "kind": "free-text", "prompt": "Feedback", "required": false}]'::jsonb,
                2,
                'ready',
                'Accepted survey',

                '2030-01-03 10:00:00+00',
                '2030-01-02 10:00:00+00',
                'Tell us how it went',
                '2030-01-01 12:00:00+00',
                '2030-01-01 10:00:00+00',
                0,
                '2030-01-01 10:00:00+00',
                '2030-01-01 11:00:00+00'
            )
        $$,
        :'eventID'
    ),
    'Should accept surveys with every optional setting'
);

-- Should clear the creator when the creating user is deleted
select lives_ok(
    format($$delete from "user" where user_id = %L::uuid$$, :'creatorUserID'),
    'Should delete users who created surveys'
);
select is(
    (select created_by from event_survey where event_survey_id = :'creatorSurveyID'),
    null::uuid,
    'Should clear the creator when the creating user is deleted'
);

-- Should delete surveys when their event is deleted
select lives_ok(
    format($$delete from event where event_id = %L::uuid$$, :'cascadeEventID'),
    'Should delete events with surveys'
);
select is(
    (select count(*)::int from event_survey where event_survey_id = :'cascadeSurveyID'),
    0,
    'Should delete surveys when their event is deleted'
);

-- Should reject blank descriptions
select throws_ok(
    format(
        $$
            insert into event_survey (event_id, title, description)
            values (%L::uuid, 'Survey', '   ')
        $$,
        :'eventID'
    ),
    '23514',
    'new row for relation "event_survey" violates check constraint "event_survey_description_chk"',
    'Should reject blank descriptions'
);

-- Should reject blank titles
select throws_ok(
    format(
        $$
            insert into event_survey (event_id, title)
            values (%L::uuid, '   ')
        $$,
        :'eventID'
    ),
    '23514',
    'new row for relation "event_survey" violates check constraint "event_survey_title_chk"',
    'Should reject blank titles'
);

-- Should reject closing dates that are not after the opening date
select throws_ok(
    format(
        $$
            insert into event_survey (event_id, title, closes_at, opens_at)
            values (%L::uuid, 'Survey', '2030-01-01 10:00:00+00', '2030-01-01 10:00:00+00')
        $$,
        :'eventID'
    ),
    '23514',
    'new row for relation "event_survey" violates check constraint "event_survey_dates_chk"',
    'Should reject closing dates that are not after the opening date'
);

-- Should reject drafts with closing times
select throws_ok(
    format(
        $$
            insert into event_survey (event_id, title, closed_at)
            values (%L::uuid, 'Survey', '2030-01-03 10:00:00+00')
        $$,
        :'eventID'
    ),
    '23514',
    'new row for relation "event_survey" violates check constraint "event_survey_draft_chk"',
    'Should reject drafts with closing times'
);

-- Should reject drafts with first response times
select throws_ok(
    format(
        $$
            insert into event_survey (event_id, title, first_response_at)
            values (%L::uuid, 'Survey', '2030-01-01 12:00:00+00')
        $$,
        :'eventID'
    ),
    '23514',
    'new row for relation "event_survey" violates check constraint "event_survey_draft_chk"',
    'Should reject drafts with first response times'
);

-- Should reject drafts with processed opening notifications
select throws_ok(
    format(
        $$
            insert into event_survey (
                event_id,
                title,
                open_notification_processed_at,
                open_notification_recipients
            ) values (%L::uuid, 'Survey', '2030-01-01 10:00:00+00', 0)
        $$,
        :'eventID'
    ),
    '23514',
    'new row for relation "event_survey" violates check constraint "event_survey_draft_chk"',
    'Should reject drafts with processed opening notifications'
);

-- Should reject negative opening notification recipient counts
select throws_ok(
    format(
        $$
            insert into event_survey (
                event_id,
                status,
                title,
                open_notification_processed_at,
                open_notification_recipients
            ) values (%L::uuid, 'ready', 'Survey', '2030-01-01 10:00:00+00', -1)
        $$,
        :'eventID'
    ),
    '23514',
    'new row for relation "event_survey" violates check constraint "event_survey_open_notification_chk"',
    'Should reject negative opening notification recipient counts'
);

-- Should reject non-array questions
select throws_ok(
    format(
        $$
            insert into event_survey (event_id, title, questions)
            values (%L::uuid, 'Survey', '{}'::jsonb)
        $$,
        :'eventID'
    ),
    '23514',
    'new row for relation "event_survey" violates check constraint "event_survey_questions_chk"',
    'Should reject non-array questions'
);

-- Should reject non-positive revisions
select throws_ok(
    format(
        $$
            insert into event_survey (event_id, title, revision)
            values (%L::uuid, 'Survey', 0)
        $$,
        :'eventID'
    ),
    '23514',
    'new row for relation "event_survey" violates check constraint "event_survey_revision_chk"',
    'Should reject non-positive revisions'
);

-- Should reject opening notification recipients without a processing time
select throws_ok(
    format(
        $$
            insert into event_survey (event_id, status, title, open_notification_recipients)
            values (%L::uuid, 'ready', 'Survey', 0)
        $$,
        :'eventID'
    ),
    '23514',
    'new row for relation "event_survey" violates check constraint "event_survey_open_notification_chk"',
    'Should reject opening notification recipients without a processing time'
);

-- Should reject processed opening notifications without recipients
select throws_ok(
    format(
        $$
            insert into event_survey (event_id, status, title, open_notification_processed_at)
            values (%L::uuid, 'ready', 'Survey', '2030-01-01 10:00:00+00')
        $$,
        :'eventID'
    ),
    '23514',
    'new row for relation "event_survey" violates check constraint "event_survey_open_notification_chk"',
    'Should reject processed opening notifications without recipients'
);

-- Should reject unknown audiences
select throws_ok(
    format(
        $$
            insert into event_survey (event_id, title, audience)
            values (%L::uuid, 'Survey', 'everyone')
        $$,
        :'eventID'
    ),
    '23514',
    'new row for relation "event_survey" violates check constraint "event_survey_audience_chk"',
    'Should reject unknown audiences'
);

-- Should reject unknown statuses
select throws_ok(
    format(
        $$
            insert into event_survey (event_id, title, status)
            values (%L::uuid, 'Survey', 'open')
        $$,
        :'eventID'
    ),
    '23514',
    'new row for relation "event_survey" violates check constraint "event_survey_status_chk"',
    'Should reject unknown statuses'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
