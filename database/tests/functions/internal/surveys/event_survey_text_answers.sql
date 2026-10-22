-- Tests listing the non-blank free-text answers of a survey.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set blankQuestionID 'a5e00041-0000-0000-0000-000000000001'
\set blankUserID 'a5e00041-0000-0000-0000-000000000002'
\set communityID 'a5e00041-0000-0000-0000-000000000003'
\set earliestUserID 'a5e00041-0000-0000-0000-000000000004'
\set eventCategoryID 'a5e00041-0000-0000-0000-000000000005'
\set eventID 'a5e00041-0000-0000-0000-000000000006'
\set groupCategoryID 'a5e00041-0000-0000-0000-000000000007'
\set groupID 'a5e00041-0000-0000-0000-000000000008'
\set invalidIDUserID 'a5e00041-0000-0000-0000-000000000009'
\set latestUserID 'a5e00041-0000-0000-0000-00000000000a'
\set malformedQuestionID 'a5e00041-0000-0000-0000-00000000000b'
\set malformedUserID 'a5e00041-0000-0000-0000-00000000000c'
\set nonStringQuestionID 'a5e00041-0000-0000-0000-00000000000d'
\set nonStringUserID 'a5e00041-0000-0000-0000-00000000000e'
\set otherSurveyID 'a5e00041-0000-0000-0000-00000000000f'
\set otherSurveyUserID 'a5e00041-0000-0000-0000-000000000010'
\set surveyID 'a5e00041-0000-0000-0000-000000000011'
\set textQuestionID 'a5e00041-0000-0000-0000-000000000012'
\set tieFirstUserID 'a5e00041-0000-0000-0000-000000000013'
\set tieSecondUserID 'a5e00041-0000-0000-0000-000000000014'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community hosting the surveyed event
select fx_community(:'communityID');

-- Respondent with blank answers
select fx_user(:'blankUserID');

-- Earliest respondent
select fx_user(:'earliestUserID');

-- Respondent answering a question with an invalid identifier
select fx_user(:'invalidIDUserID');

-- Latest respondent
select fx_user(:'latestUserID');

-- Respondent whose answers are not an array
select fx_user(:'malformedUserID');

-- Respondent with non-string answers
select fx_user(:'nonStringUserID');

-- Respondent of another survey
select fx_user(:'otherSurveyUserID');

-- First respondent of two answering at the same time
select fx_user(:'tieFirstUserID');

-- Second respondent of two answering at the same time
select fx_user(:'tieSecondUserID');

-- Event category used by the surveyed event
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category used by the surveyed event group
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group hosting the surveyed event
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event owning the surveys
select fx_event(:'eventID', :'groupID', :'eventCategoryID');

-- Another survey answering the same question identifier
insert into event_survey (event_survey_id, event_id, status, title)
values (:'otherSurveyID', :'eventID', 'ready', 'Other feedback');

-- Survey whose answers are listed
insert into event_survey (event_survey_id, event_id, status, title)
values (:'surveyID', :'eventID', 'ready', 'Feedback');

-- Response of another survey to the same question identifier
insert into event_survey_response (event_survey_id, user_id, answers, created_at)
values (:'otherSurveyID', :'otherSurveyUserID', jsonb_build_object('answers', jsonb_build_array(
    jsonb_build_object('question_id', :'textQuestionID', 'value', 'Other survey answer')
)), current_timestamp - interval '6 hours');

-- Response with blank and non-string answers
insert into event_survey_response (event_survey_id, user_id, answers, created_at)
values (:'surveyID', :'blankUserID', jsonb_build_object('answers', jsonb_build_array(
    jsonb_build_object('question_id', :'blankQuestionID', 'value', '   '),
    jsonb_build_object('question_id', :'nonStringQuestionID', 'value', jsonb_build_array(:'textQuestionID')),
    jsonb_build_object('question_id', :'textQuestionID', 'value', '   ')
)), current_timestamp - interval '4 hours');

-- Earliest response, with an empty answer and a non-string answer
insert into event_survey_response (event_survey_id, user_id, answers, created_at)
values (:'surveyID', :'earliestUserID', jsonb_build_object('answers', jsonb_build_array(
    jsonb_build_object('question_id', :'blankQuestionID', 'value', ''),
    jsonb_build_object('question_id', :'nonStringQuestionID', 'value', 42),
    jsonb_build_object('question_id', :'textQuestionID', 'value', 'Earliest answer')
)), current_timestamp - interval '5 hours');

-- Response answering a question with an invalid identifier
insert into event_survey_response (event_survey_id, user_id, answers, created_at)
values (:'surveyID', :'invalidIDUserID', jsonb_build_object('answers', jsonb_build_array(
    jsonb_build_object('question_id', 'not-a-uuid', 'value', 'Invalid identifier answer')
)), current_timestamp - interval '90 minutes');

-- Latest response
insert into event_survey_response (event_survey_id, user_id, answers, created_at)
values (:'surveyID', :'latestUserID', jsonb_build_object('answers', jsonb_build_array(
    jsonb_build_object('question_id', :'textQuestionID', 'value', 'Latest answer')
)), current_timestamp - interval '30 minutes');

-- Response whose answers are not an array
insert into event_survey_response (event_survey_id, user_id, answers, created_at)
values (:'surveyID', :'malformedUserID', jsonb_build_object('answers', jsonb_build_object(
    'question_id', :'malformedQuestionID',
    'value', 'Malformed answer'
)), current_timestamp - interval '2 hours');

-- Response with non-string answers only
insert into event_survey_response (event_survey_id, user_id, answers, created_at)
values (:'surveyID', :'nonStringUserID', jsonb_build_object('answers', jsonb_build_array(
    jsonb_build_object('question_id', :'nonStringQuestionID', 'value', true),
    jsonb_build_object('question_id', :'textQuestionID', 'value', 7)
)), current_timestamp - interval '3 hours');

-- First of two responses created at the same time
insert into event_survey_response (event_survey_id, user_id, answers, created_at)
values (:'surveyID', :'tieFirstUserID', jsonb_build_object('answers', jsonb_build_array(
    jsonb_build_object('question_id', :'textQuestionID', 'value', 'Tie first answer')
)), current_timestamp - interval '1 hour');

-- Second of two responses created at the same time
insert into event_survey_response (event_survey_id, user_id, answers, created_at)
values (:'surveyID', :'tieSecondUserID', jsonb_build_object('answers', jsonb_build_array(
    jsonb_build_object('question_id', :'textQuestionID', 'value', 'Tie second answer')
)), current_timestamp - interval '1 hour');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should ignore blank answers
select is(
    (
        select count(*)::int
        from event_survey_text_answers(:'surveyID') a
        where a.question_id = :'blankQuestionID'
    ),
    0,
    'Should ignore blank answers'
);

-- Should ignore answers with invalid question identifiers
select is(
    (
        select count(*)::int
        from event_survey_text_answers(:'surveyID') a
        where a.value = 'Invalid identifier answer'
    ),
    0,
    'Should ignore answers with invalid question identifiers'
);

-- Should ignore non-string answers
select is(
    (
        select count(*)::int
        from event_survey_text_answers(:'surveyID') a
        where a.question_id = :'nonStringQuestionID'
    ),
    0,
    'Should ignore non-string answers'
);

-- Should ignore responses whose answers are not an array
select is(
    (
        select count(*)::int
        from event_survey_text_answers(:'surveyID') a
        where a.question_id = :'malformedQuestionID'
    ),
    0,
    'Should ignore responses whose answers are not an array'
);

-- Should return the non-blank answers of the survey with their respondents
select results_eq(
    format(
        $$
            select
                a.question_id,
                a.user_id,
                a.value
            from event_survey_text_answers(%L::uuid) a
            order by a.created_at, a.user_id
        $$,
        :'surveyID'
    ),
    format(
        $$
            values
                (%L::uuid, %L::uuid, 'Earliest answer'),
                (%L::uuid, %L::uuid, 'Tie first answer'),
                (%L::uuid, %L::uuid, 'Tie second answer'),
                (%L::uuid, %L::uuid, 'Latest answer')
        $$,
        :'textQuestionID', :'earliestUserID',
        :'textQuestionID', :'tieFirstUserID',
        :'textQuestionID', :'tieSecondUserID',
        :'textQuestionID', :'latestUserID'
    ),
    'Should return the non-blank answers of the survey with their respondents'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
