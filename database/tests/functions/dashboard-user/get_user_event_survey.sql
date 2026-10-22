-- Tests loading the survey a user answers from the dashboard.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set canceledEventID 'a5e00032-0000-0000-0000-000000000001'
\set canceledEventSurveyID 'a5e00032-0000-0000-0000-000000000002'
\set closedAnsweredSurveyID 'a5e00032-0000-0000-0000-000000000024'
\set communityID 'a5e00032-0000-0000-0000-000000000004'
\set eventCategoryID 'a5e00032-0000-0000-0000-00000000000b'
\set eventID 'a5e00032-0000-0000-0000-00000000000c'
\set groupCategoryID 'a5e00032-0000-0000-0000-00000000000d'
\set groupID 'a5e00032-0000-0000-0000-00000000000e'
\set lateOpeningSurveyID 'a5e00032-0000-0000-0000-000000000021'
\set openSurveyID 'a5e00032-0000-0000-0000-000000000018'
\set outsiderID 'a5e00032-0000-0000-0000-000000000019'
\set questionID 'a5e00032-0000-0000-0000-00000000001a'
\set respondentID 'a5e00032-0000-0000-0000-00000000001b'
\set unansweredAttendeeID 'a5e00032-0000-0000-0000-000000000023'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Active community hosting the surveyed events
select fx_community(:'communityID', jsonb_build_object('active', true));

-- User outside the survey audience
select fx_user(:'outsiderID');

-- Confirmed attendee who answered the open survey
select fx_user(:'respondentID');

-- Confirmed attendee who has not answered the open survey
select fx_user(:'unansweredAttendeeID');

-- Event category of the active community
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category of the active community
select fx_group_category(:'groupCategoryID', :'communityID');

-- Active group hosting the public surveyed event
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object('active', true));

-- Canceled published event that already ended
select fx_event(:'canceledEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'ends_at', current_timestamp - interval '2 days',
    'published', true,
    'starts_at', current_timestamp - interval '2 days 2 hours'
));

-- Published ended event hosting the answered surveys
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp - interval '2 days',
    'published', true,
    'starts_at', current_timestamp - interval '2 days 2 hours'
));

-- Confirmed attendee of the canceled event, so only the public check hides its survey
insert into event_attendee (event_id, user_id, status)
values (:'canceledEventID', :'respondentID', 'confirmed');

-- Confirmed attendee of the public event
insert into event_attendee (event_id, user_id, status)
values (:'eventID', :'respondentID', 'confirmed');

-- Confirmed attendee of the public event without a response
insert into event_attendee (event_id, user_id, status)
values (:'eventID', :'unansweredAttendeeID', 'confirmed');

-- Ready survey of the canceled event
insert into event_survey (event_survey_id, event_id, status, title)
values (:'canceledEventSurveyID', :'canceledEventID', 'ready', 'Canceled event survey');

-- Anonymous survey the respondent answered, closed manually on the public event
insert into event_survey (
    event_survey_id,
    event_id,
    questions,
    revision,
    status,
    title,

    closed_at,
    closes_at,
    first_response_at
) values (
    :'closedAnsweredSurveyID',
    :'eventID',
    jsonb_build_array(jsonb_build_object(
        'id', :'questionID'::uuid,
        'kind', 'free-text',
        'prompt', 'Feedback',
        'required', false
    )),
    2,
    'ready',
    'Closed answered survey',

    current_timestamp - interval '1 hour',
    current_timestamp + interval '5 days',
    current_timestamp - interval '1 day'
);

-- Open survey whose custom opening is later than the event end
insert into event_survey (event_survey_id, event_id, status, title, opens_at)
values (:'lateOpeningSurveyID', :'eventID', 'ready', 'Late opening survey', current_timestamp - interval '1 day');

-- Open identified survey with every optional field set
insert into event_survey (
    event_survey_id,
    anonymous,
    audience,
    event_id,
    questions,
    revision,
    status,
    title,

    closes_at,
    description,
    first_response_at
) values (
    :'openSurveyID',
    false,
    'confirmed',
    :'eventID',
    jsonb_build_array(jsonb_build_object(
        'id', :'questionID'::uuid,
        'kind', 'free-text',
        'prompt', 'Feedback',
        'required', false
    )),
    3,
    'ready',
    'Open survey',

    current_timestamp + interval '5 days',
    'Tell us how it went',
    current_timestamp - interval '1 day'
);

-- Response of the confirmed attendee to the closed survey
insert into event_survey_response (answers, created_at, event_survey_id, user_id)
values (
    jsonb_build_object('answers', jsonb_build_array(jsonb_build_object(
        'question_id', :'questionID'::uuid,
        'value', 'Well organized'
    ))),
    current_timestamp - interval '1 day',
    :'closedAnsweredSurveyID',
    :'respondentID'
);

-- Edited response of the confirmed attendee
insert into event_survey_response (answers, created_at, event_survey_id, user_id, updated_at)
values (
    jsonb_build_object('answers', jsonb_build_array(jsonb_build_object(
        'question_id', :'questionID'::uuid,
        'value', 'Great'
    ))),
    current_timestamp - interval '1 day',
    :'openSurveyID',
    :'respondentID',
    current_timestamp - interval '1 hour'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return a null response for eligible users who have not answered
select is(
    get_user_event_survey(:'openSurveyID'::uuid, :'unansweredAttendeeID'::uuid)::jsonb->'response',
    'null'::jsonb,
    'Should return a null response for eligible users who have not answered'
);

-- Should return closed surveys the user answered with their answers
select is(
    get_user_event_survey(:'closedAnsweredSurveyID'::uuid, :'respondentID'::uuid)::jsonb,
    jsonb_build_object(
        'anonymous', true,
        'event', get_event_summary(:'communityID'::uuid, :'groupID'::uuid, :'eventID'::uuid)::jsonb,
        'event_survey_id', :'closedAnsweredSurveyID'::uuid,
        'questions', jsonb_build_array(jsonb_build_object(
            'id', :'questionID'::uuid,
            'kind', 'free-text',
            'prompt', 'Feedback',
            'required', false
        )),
        'revision', 2,
        'state', 'closed',
        'title', 'Closed answered survey',

        'closed_at', epoch_seconds(current_timestamp - interval '1 hour'),
        'closes_at', epoch_seconds(current_timestamp + interval '5 days'),
        'description', null,
        'response', jsonb_build_object(
            'answers', jsonb_build_object('answers', jsonb_build_array(jsonb_build_object(
                'question_id', :'questionID'::uuid,
                'value', 'Well organized'
            ))),
            'created_at', epoch_seconds(current_timestamp - interval '1 day'),

            'updated_at', null
        )
    ),
    'Should return closed surveys the user answered with their answers'
);

-- Should return null for surveys of canceled events
select is(
    get_user_event_survey(:'canceledEventSurveyID'::uuid, :'respondentID'::uuid)::jsonb,
    null,
    'Should return null for surveys of canceled events'
);

-- Should return null for unknown surveys
select is(
    get_user_event_survey(:'questionID'::uuid, :'respondentID'::uuid)::jsonb,
    null,
    'Should return null for unknown surveys'
);

-- Should return null for users outside the survey audience
select is(
    get_user_event_survey(:'openSurveyID'::uuid, :'outsiderID'::uuid)::jsonb,
    null,
    'Should return null for users outside the survey audience'
);

-- Should return surveys whose custom opening later than the event end has passed
select is(
    get_user_event_survey(:'lateOpeningSurveyID'::uuid, :'respondentID'::uuid)::jsonb->>'event_survey_id',
    :'lateOpeningSurveyID',
    'Should return surveys whose custom opening later than the event end has passed'
);

-- Should return the survey with the eligible user response
select is(
    get_user_event_survey(:'openSurveyID'::uuid, :'respondentID'::uuid)::jsonb,
    jsonb_build_object(
        'anonymous', false,
        'event', get_event_summary(:'communityID'::uuid, :'groupID'::uuid, :'eventID'::uuid)::jsonb,
        'event_survey_id', :'openSurveyID'::uuid,
        'questions', jsonb_build_array(jsonb_build_object(
            'id', :'questionID'::uuid,
            'kind', 'free-text',
            'prompt', 'Feedback',
            'required', false
        )),
        'revision', 3,
        'state', 'open',
        'title', 'Open survey',

        'closed_at', null,
        'closes_at', epoch_seconds(current_timestamp + interval '5 days'),
        'description', 'Tell us how it went',
        'response', jsonb_build_object(
            'answers', jsonb_build_object('answers', jsonb_build_array(jsonb_build_object(
                'question_id', :'questionID'::uuid,
                'value', 'Great'
            ))),
            'created_at', epoch_seconds(current_timestamp - interval '1 day'),

            'updated_at', epoch_seconds(current_timestamp - interval '1 hour')
        )
    ),
    'Should return the survey with the eligible user response'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
