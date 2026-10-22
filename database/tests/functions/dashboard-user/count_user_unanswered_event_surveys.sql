-- Tests counting the open surveys a user has not answered yet.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set answeredSurveyID 'a5e00038-0000-0000-0000-000000000001'
\set closedSurveyID 'a5e00038-0000-0000-0000-000000000002'
\set communityID 'a5e00038-0000-0000-0000-000000000003'
\set completeRespondentID 'a5e00038-0000-0000-0000-000000000004'
\set eventCategoryID 'a5e00038-0000-0000-0000-000000000005'
\set eventID 'a5e00038-0000-0000-0000-000000000006'
\set firstUnansweredSurveyID 'a5e00038-0000-0000-0000-000000000007'
\set groupCategoryID 'a5e00038-0000-0000-0000-000000000008'
\set groupID 'a5e00038-0000-0000-0000-000000000009'
\set outsiderID 'a5e00038-0000-0000-0000-00000000000a'
\set respondentID 'a5e00038-0000-0000-0000-00000000000b'
\set scheduledSurveyID 'a5e00038-0000-0000-0000-00000000000c'
\set secondUnansweredSurveyID 'a5e00038-0000-0000-0000-00000000000d'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Active community hosting the surveyed event
select fx_community(:'communityID', jsonb_build_object('active', true));

-- Confirmed attendee who answered every open survey
select fx_user(:'completeRespondentID');

-- User outside every survey audience
select fx_user(:'outsiderID');

-- Confirmed attendee who answered one open survey
select fx_user(:'respondentID');

-- Event category of the community
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category of the community
select fx_group_category(:'groupCategoryID', :'communityID');

-- Active group hosting the surveyed event
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object('active', true));

-- Published event that already ended
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp - interval '2 days',
    'published', true,
    'starts_at', current_timestamp - interval '2 days 2 hours'
));

-- Confirmed attendance of both respondents
insert into event_attendee (checked_in, event_id, status, user_id)
select false, :'eventID', 'confirmed', user_id
from unnest(array[:'completeRespondentID', :'respondentID']::uuid[]) as user_id;

-- Open survey both respondents answered
insert into event_survey (event_survey_id, event_id, status, title)
values (:'answeredSurveyID', :'eventID', 'ready', 'Answered');

-- Survey closed manually without responses
insert into event_survey (event_survey_id, event_id, status, title, closed_at)
values (:'closedSurveyID', :'eventID', 'ready', 'Closed', current_timestamp - interval '1 hour');

-- First open survey only the complete respondent answered
insert into event_survey (event_survey_id, event_id, status, title)
values (:'firstUnansweredSurveyID', :'eventID', 'ready', 'First unanswered');

-- Ready survey whose custom opening is in the future
insert into event_survey (event_survey_id, event_id, status, title, opens_at)
values (:'scheduledSurveyID', :'eventID', 'ready', 'Scheduled', current_timestamp + interval '1 day');

-- Second open survey only the complete respondent answered
insert into event_survey (event_survey_id, event_id, status, title)
values (:'secondUnansweredSurveyID', :'eventID', 'ready', 'Second unanswered');

-- Responses of the complete respondent to every open survey
insert into event_survey_response (answers, event_survey_id, user_id)
select '{"answers": []}'::jsonb, event_survey_id, :'completeRespondentID'
from unnest(array[
    :'answeredSurveyID',
    :'firstUnansweredSurveyID',
    :'secondUnansweredSurveyID'
]::uuid[]) as event_survey_id;

-- Response of the respondent to the answered survey
insert into event_survey_response (answers, event_survey_id, user_id)
values ('{"answers": []}'::jsonb, :'answeredSurveyID', :'respondentID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should count only the open surveys the user has not answered
select is(
    count_user_unanswered_event_surveys(:'respondentID'::uuid),
    2,
    'Should count only the open surveys the user has not answered'
);

-- Should return zero when the user answered every open survey
select is(
    count_user_unanswered_event_surveys(:'completeRespondentID'::uuid),
    0,
    'Should return zero when the user answered every open survey'
);

-- Should return zero for users outside every audience
select is(
    count_user_unanswered_event_surveys(:'outsiderID'::uuid),
    0,
    'Should return zero for users outside every audience'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
