-- Tests loading the details of the response of a user to a survey.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set adaUserID 'a5e0001d-0000-0000-0000-000000000001'
\set communityID 'a5e0001d-0000-0000-0000-000000000002'
\set eventCategoryID 'a5e0001d-0000-0000-0000-000000000003'
\set eventID 'a5e0001d-0000-0000-0000-000000000004'
\set graceUserID 'a5e0001d-0000-0000-0000-000000000005'
\set groupCategoryID 'a5e0001d-0000-0000-0000-000000000006'
\set groupID 'a5e0001d-0000-0000-0000-000000000007'
\set linusUserID 'a5e0001d-0000-0000-0000-000000000008'
\set malformedUserID 'a5e0001d-0000-0000-0000-000000000009'
\set multiOptionID 'a5e0001d-0000-0000-0000-00000000000a'
\set multiQuestionID 'a5e0001d-0000-0000-0000-00000000000b'
\set otherSurveyID 'a5e0001d-0000-0000-0000-00000000000c'
\set otherSurveyUserID 'a5e0001d-0000-0000-0000-00000000000d'
\set singleOptionID 'a5e0001d-0000-0000-0000-00000000000e'
\set singleQuestionID 'a5e0001d-0000-0000-0000-00000000000f'
\set surveyID 'a5e0001d-0000-0000-0000-000000000010'
\set textQuestionID 'a5e0001d-0000-0000-0000-000000000011'
\set ticketTypeID 'a5e0001d-0000-0000-0000-000000000012'
\set unknownQuestionID 'a5e0001d-0000-0000-0000-000000000013'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community hosting the surveyed event
select fx_community(:'communityID');

-- Respondent with every profile detail
select fx_user(:'adaUserID', jsonb_build_object(
    'company', 'Analytical Engines',
    'name', 'Ada Lovelace',
    'title', 'Countess',
    'username', 'details-ada'
));

-- Respondent with a refunded purchase
select fx_user(:'graceUserID');

-- Respondent with a pending purchase
select fx_user(:'linusUserID');

-- Respondent whose answers are not an array
select fx_user(:'malformedUserID');

-- Respondent of another survey of the event
select fx_user(:'otherSurveyUserID');

-- Event category used by the surveyed event
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category used by the surveyed event group
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group hosting the surveyed event
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event owning the surveys
select fx_event(:'eventID', :'groupID', :'eventCategoryID');

-- Another survey of the event
insert into event_survey (event_survey_id, anonymous, event_id, status, title)
values (:'otherSurveyID', false, :'eventID', 'ready', 'Other feedback');

-- Survey with a free-text, a single-select and a multi-select question
insert into event_survey (event_survey_id, anonymous, event_id, questions, status, title)
values (
    :'surveyID',
    false,
    :'eventID',
    jsonb_build_array(
        jsonb_build_object('id', :'textQuestionID', 'kind', 'free-text', 'options', '[]'::jsonb, 'prompt', 'Comments', 'required', false),
        jsonb_build_object('id', :'singleQuestionID', 'kind', 'single-select', 'options', jsonb_build_array(
            jsonb_build_object('id', :'singleOptionID', 'label', 'Good')
        ), 'prompt', 'Rating', 'required', false),
        jsonb_build_object('id', :'multiQuestionID', 'kind', 'multi-select', 'options', jsonb_build_array(
            jsonb_build_object('id', :'multiOptionID', 'label', 'Rust')
        ), 'prompt', 'Topics', 'required', false)
    ),
    'ready',
    'Feedback'
);

-- Ticket type of the surveyed event
select fx_event_ticket_type(:'ticketTypeID', :'eventID');

-- Earlier purchase of the first respondent whose refund is in flight
insert into event_purchase (
    amount_minor,
    created_at,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id
) values (
    0,
    '2025-01-01 08:00:00+00',
    :'eventID',
    :'ticketTypeID',
    'refund-pending',
    'Early bird',
    :'adaUserID'
);

-- Latest completed purchase of the first respondent
insert into event_purchase (
    amount_minor,
    created_at,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id
) values (
    0,
    '2025-01-01 09:00:00+00',
    :'eventID',
    :'ticketTypeID',
    'completed',
    'VIP',
    :'adaUserID'
);

-- Refunded purchase of the second respondent
insert into event_purchase (
    amount_minor,
    created_at,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id
) values (
    0,
    '2025-01-01 09:00:00+00',
    :'eventID',
    :'ticketTypeID',
    'refunded',
    'Refunded ticket',
    :'graceUserID'
);

-- Pending purchase of the third respondent
insert into event_purchase (
    amount_minor,
    created_at,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    status,
    ticket_title,
    user_id
) values (
    0,
    '2025-01-01 09:00:00+00',
    :'eventID',
    :'ticketTypeID',
    '2099-01-01 09:00:00+00',
    'pending',
    'Pending ticket',
    :'linusUserID'
);

-- Edited response answering every question
insert into event_survey_response (answers, created_at, event_survey_id, user_id, updated_at)
values (
    jsonb_build_object('answers', jsonb_build_array(
        jsonb_build_object('question_id', :'textQuestionID', 'value', 'Loved it'),
        jsonb_build_object('question_id', :'singleQuestionID', 'value', :'singleOptionID'),
        jsonb_build_object('question_id', :'multiQuestionID', 'value', jsonb_build_array(:'multiOptionID'))
    )),
    '2025-01-02 09:00:00+00',
    :'surveyID',
    :'adaUserID',
    '2025-01-02 09:30:00+00'
);

-- Response with a blank text, no selected options and an unknown question
insert into event_survey_response (answers, created_at, event_survey_id, user_id)
values (
    jsonb_build_object('answers', jsonb_build_array(
        jsonb_build_object('question_id', :'textQuestionID', 'value', '   '),
        jsonb_build_object('question_id', :'multiQuestionID', 'value', '[]'::jsonb),
        jsonb_build_object('question_id', :'unknownQuestionID', 'value', 'Unknown')
    )),
    '2025-01-02 09:01:00+00',
    :'surveyID',
    :'graceUserID'
);

-- Response answering only the single-select question
insert into event_survey_response (answers, created_at, event_survey_id, user_id)
values (
    jsonb_build_object('answers', jsonb_build_array(
        jsonb_build_object('question_id', :'textQuestionID', 'value', ''),
        jsonb_build_object('question_id', :'singleQuestionID', 'value', :'singleOptionID')
    )),
    '2025-01-02 09:02:00+00',
    :'surveyID',
    :'linusUserID'
);

-- Response whose answers are not an array
insert into event_survey_response (answers, created_at, event_survey_id, user_id)
values (
    jsonb_build_object('answers', jsonb_build_object(
        'question_id', :'textQuestionID',
        'value', 'Malformed'
    )),
    '2025-01-02 09:03:00+00',
    :'surveyID',
    :'malformedUserID'
);

-- Response to another survey of the event
insert into event_survey_response (answers, created_at, event_survey_id, user_id)
values (
    jsonb_build_object('answers', jsonb_build_array(
        jsonb_build_object('question_id', :'textQuestionID', 'value', 'Other survey')
    )),
    '2025-01-02 08:00:00+00',
    :'otherSurveyID',
    :'otherSurveyUserID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should count the questions each response answers
select results_eq(
    format(
        $$
            select respondent.user_id, d.answered_questions_count
            from (values (%L::uuid, 1), (%L::uuid, 2), (%L::uuid, 3), (%L::uuid, 4))
                as respondent(user_id, position)
            cross join lateral event_survey_response_details(%L::uuid, respondent.user_id) d
            order by respondent.position
        $$,
        :'adaUserID',
        :'graceUserID',
        :'linusUserID',
        :'malformedUserID',
        :'surveyID'
    ),
    format(
        $$
            values
                (%L::uuid, 3),
                (%L::uuid, 0),
                (%L::uuid, 1),
                (%L::uuid, 0)
        $$,
        :'adaUserID',
        :'graceUserID',
        :'linusUserID',
        :'malformedUserID'
    ),
    'Should count the questions each response answers'
);

-- Should return the answers, edit date and summary of the response
select is(
    (
        select jsonb_build_object(
            'answers', d.answers,
            'updated_at', d.updated_at,
            'user_summary', d.user_summary
        )
        from event_survey_response_details(:'surveyID'::uuid, :'adaUserID'::uuid) d
    ),
    jsonb_build_object(
        'answers', jsonb_build_object('answers', jsonb_build_array(
            jsonb_build_object('question_id', :'textQuestionID', 'value', 'Loved it'),
            jsonb_build_object('question_id', :'singleQuestionID', 'value', :'singleOptionID'),
            jsonb_build_object('question_id', :'multiQuestionID', 'value', jsonb_build_array(:'multiOptionID'))
        )),
        'updated_at', '2025-01-02 09:30:00+00'::timestamptz,
        'user_summary', jsonb_build_object(
            'user_id', :'adaUserID'::uuid,
            'username', 'details-ada',

            'company', 'Analytical Engines',
            'name', 'Ada Lovelace',
            'title', 'Countess'
        )
    ),
    'Should return the answers, edit date and summary of the response'
);

-- Should return nothing for users who did not answer the survey
select is_empty(
    format(
        $$ select * from event_survey_response_details(%L::uuid, %L::uuid) $$,
        :'surveyID',
        :'otherSurveyUserID'
    ),
    'Should return nothing for users who did not answer the survey'
);

-- Should return only the response to the requested survey
select results_eq(
    format(
        $$
            select d.answers
            from event_survey_response_details(%L::uuid, %L::uuid) d
        $$,
        :'otherSurveyID',
        :'otherSurveyUserID'
    ),
    format(
        $$ values (jsonb_build_object('answers', jsonb_build_array(jsonb_build_object('question_id', %L, 'value', 'Other survey')))) $$,
        :'textQuestionID'
    ),
    'Should return only the response to the requested survey'
);

-- Should return the ticket title of the latest seat-holding purchase
select results_eq(
    format(
        $$
            select respondent.user_id, d.ticket_title
            from (values (%L::uuid, 1), (%L::uuid, 2), (%L::uuid, 3), (%L::uuid, 4))
                as respondent(user_id, position)
            cross join lateral event_survey_response_details(%L::uuid, respondent.user_id) d
            order by respondent.position
        $$,
        :'adaUserID',
        :'graceUserID',
        :'linusUserID',
        :'malformedUserID',
        :'surveyID'
    ),
    format(
        $$
            values
                (%L::uuid, 'VIP'::text),
                (%L::uuid, null::text),
                (%L::uuid, null::text),
                (%L::uuid, null::text)
        $$,
        :'adaUserID',
        :'graceUserID',
        :'linusUserID',
        :'malformedUserID'
    ),
    'Should return the ticket title of the latest seat-holding purchase'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
