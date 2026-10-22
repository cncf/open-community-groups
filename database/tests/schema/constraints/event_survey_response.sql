-- Tests event survey response constraints.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set cascadeSurveyID 'a5e00002-0000-0000-0000-000000000001'
\set cascadeUserID 'a5e00002-0000-0000-0000-000000000002'
\set communityID 'a5e00002-0000-0000-0000-000000000003'
\set eventCategoryID 'a5e00002-0000-0000-0000-000000000004'
\set eventID 'a5e00002-0000-0000-0000-000000000005'
\set groupCategoryID 'a5e00002-0000-0000-0000-000000000006'
\set groupID 'a5e00002-0000-0000-0000-000000000007'
\set otherUserID 'a5e00002-0000-0000-0000-00000000000a'
\set respondentUserID 'a5e00002-0000-0000-0000-000000000008'
\set surveyID 'a5e00002-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community hosting the surveyed event
select fx_community(:'communityID');

-- User whose response is deleted through the user cascade
select fx_user(:'cascadeUserID');

-- User whose invalid responses are rejected
select fx_user(:'otherUserID');

-- User who answers the surveys
select fx_user(:'respondentUserID');

-- Event category used by the surveyed event
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category used by the surveyed event group
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group hosting the surveyed event
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event owning the surveys
select fx_event(:'eventID', :'groupID', :'eventCategoryID');

-- Survey deleted together with its responses
insert into event_survey (event_survey_id, event_id, title)
values (:'cascadeSurveyID', :'eventID', 'Cascade survey');

-- Survey receiving the responses written by the constraint scenarios
insert into event_survey (event_survey_id, event_id, title)
values (:'surveyID', :'eventID', 'Survey');

-- Response deleted through the survey cascade
insert into event_survey_response (answers, event_survey_id, user_id)
values ('{}'::jsonb, :'cascadeSurveyID', :'respondentUserID');

-- Response deleted through the user cascade
insert into event_survey_response (answers, event_survey_id, user_id)
values ('{}'::jsonb, :'surveyID', :'cascadeUserID');

-- Response whose survey and user pair is duplicated
insert into event_survey_response (answers, event_survey_id, user_id)
values ('{}'::jsonb, :'surveyID', :'respondentUserID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should default the response creation time
select is(
    (
        select created_at = current_timestamp and updated_at is null
        from event_survey_response
        where event_survey_id = :'surveyID'
        and user_id = :'respondentUserID'
    ),
    true,
    'Should default the response creation time'
);

-- Should delete responses when their survey is deleted
select lives_ok(
    format($$delete from event_survey where event_survey_id = %L::uuid$$, :'cascadeSurveyID'),
    'Should delete surveys with responses'
);
select is(
    (select count(*)::int from event_survey_response where event_survey_id = :'cascadeSurveyID'),
    0,
    'Should delete responses when their survey is deleted'
);

-- Should delete responses when their user is deleted
select lives_ok(
    format($$delete from "user" where user_id = %L::uuid$$, :'cascadeUserID'),
    'Should delete users with responses'
);
select is(
    (select count(*)::int from event_survey_response where user_id = :'cascadeUserID'),
    0,
    'Should delete responses when their user is deleted'
);

-- Should reject duplicate responses from the same user
select throws_ok(
    format(
        $$
            insert into event_survey_response (answers, event_survey_id, user_id)
            values ('{}'::jsonb, %L::uuid, %L::uuid)
        $$,
        :'surveyID',
        :'respondentUserID'
    ),
    '23505',
    'duplicate key value violates unique constraint "event_survey_response_pkey"',
    'Should reject duplicate responses from the same user'
);

-- Should reject non-object answers
select throws_ok(
    format(
        $$
            insert into event_survey_response (answers, event_survey_id, user_id)
            values ('[]'::jsonb, %L::uuid, %L::uuid)
        $$,
        :'surveyID',
        :'otherUserID'
    ),
    '23514',
    'new row for relation "event_survey_response" violates check constraint "event_survey_response_answers_chk"',
    'Should reject non-object answers'
);

-- Should reject responses without answers
select throws_ok(
    format(
        $$
            insert into event_survey_response (event_survey_id, user_id)
            values (%L::uuid, %L::uuid)
        $$,
        :'surveyID',
        :'otherUserID'
    ),
    '23502',
    'null value in column "answers" of relation "event_survey_response" violates not-null constraint',
    'Should reject responses without answers'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
