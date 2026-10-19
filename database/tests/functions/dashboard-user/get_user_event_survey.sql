-- Tests loading the survey a user answers from the dashboard.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(16);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set canceledEventID 'a5e00032-0000-0000-0000-000000000001'
\set canceledEventSurveyID 'a5e00032-0000-0000-0000-000000000002'
\set closedSurveyID 'a5e00032-0000-0000-0000-000000000003'
\set communityID 'a5e00032-0000-0000-0000-000000000004'
\set datelessEventID 'a5e00032-0000-0000-0000-00000000001f'
\set datelessEventSurveyID 'a5e00032-0000-0000-0000-000000000020'
\set deletedEventID 'a5e00032-0000-0000-0000-000000000005'
\set deletedEventSurveyID 'a5e00032-0000-0000-0000-000000000006'
\set deletedGroupEventID 'a5e00032-0000-0000-0000-000000000007'
\set deletedGroupID 'a5e00032-0000-0000-0000-000000000008'
\set deletedGroupSurveyID 'a5e00032-0000-0000-0000-000000000009'
\set draftSurveyID 'a5e00032-0000-0000-0000-00000000000a'
\set eventCategoryID 'a5e00032-0000-0000-0000-00000000000b'
\set eventID 'a5e00032-0000-0000-0000-00000000000c'
\set groupCategoryID 'a5e00032-0000-0000-0000-00000000000d'
\set groupID 'a5e00032-0000-0000-0000-00000000000e'
\set inactiveCommunityEventCategoryID 'a5e00032-0000-0000-0000-00000000000f'
\set inactiveCommunityEventID 'a5e00032-0000-0000-0000-000000000010'
\set inactiveCommunityGroupCategoryID 'a5e00032-0000-0000-0000-000000000011'
\set inactiveCommunityGroupID 'a5e00032-0000-0000-0000-000000000012'
\set inactiveCommunityID 'a5e00032-0000-0000-0000-000000000013'
\set inactiveCommunitySurveyID 'a5e00032-0000-0000-0000-000000000014'
\set inactiveGroupEventID 'a5e00032-0000-0000-0000-000000000015'
\set inactiveGroupID 'a5e00032-0000-0000-0000-000000000016'
\set inactiveGroupSurveyID 'a5e00032-0000-0000-0000-000000000017'
\set lateOpeningSurveyID 'a5e00032-0000-0000-0000-000000000021'
\set openSurveyID 'a5e00032-0000-0000-0000-000000000018'
\set outsiderID 'a5e00032-0000-0000-0000-000000000019'
\set pendingAttendeeID 'a5e00032-0000-0000-0000-000000000022'
\set questionID 'a5e00032-0000-0000-0000-00000000001a'
\set respondentID 'a5e00032-0000-0000-0000-00000000001b'
\set scheduledSurveyID 'a5e00032-0000-0000-0000-00000000001c'
\set unansweredAttendeeID 'a5e00032-0000-0000-0000-000000000023'
\set unpublishedEventID 'a5e00032-0000-0000-0000-00000000001d'
\set unpublishedEventSurveyID 'a5e00032-0000-0000-0000-00000000001e'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Active community hosting the surveyed events
select fx_community(:'communityID', jsonb_build_object('active', true));

-- Inactive community hosting a hidden survey
select fx_community(:'inactiveCommunityID', jsonb_build_object('active', false));

-- User outside the survey audience
select fx_user(:'outsiderID');

-- Attendee with pending registration questions
select fx_user(:'pendingAttendeeID');

-- Confirmed attendee who answered the open survey
select fx_user(:'respondentID');

-- Confirmed attendee who has not answered the open survey
select fx_user(:'unansweredAttendeeID');

-- Event category of the active community
select fx_event_category(:'eventCategoryID', :'communityID');

-- Event category of the inactive community
select fx_event_category(:'inactiveCommunityEventCategoryID', :'inactiveCommunityID');

-- Group category of the active community
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group category of the inactive community
select fx_group_category(:'inactiveCommunityGroupCategoryID', :'inactiveCommunityID');

-- Deleted group of the active community
select fx_group(:'deletedGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'deleted', true
));

-- Active group hosting the public surveyed event
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object('active', true));

-- Active group of the inactive community
select fx_group(
    :'inactiveCommunityGroupID',
    :'inactiveCommunityID',
    :'inactiveCommunityGroupCategoryID',
    jsonb_build_object('active', true)
);

-- Inactive group of the active community
select fx_group(:'inactiveGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('active', false));

-- Canceled published event that already ended
select fx_event(:'canceledEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'ends_at', current_timestamp - interval '2 days',
    'published', true,
    'starts_at', current_timestamp - interval '2 days 2 hours'
));

-- Published event without dates
select fx_event(:'datelessEventID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));

-- Deleted event that already ended
select fx_event(:'deletedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'deleted', true,
    'deleted_at', current_timestamp - interval '1 day',
    'ends_at', current_timestamp - interval '2 days',
    'starts_at', current_timestamp - interval '2 days 2 hours'
));

-- Published ended event of the deleted group
select fx_event(:'deletedGroupEventID', :'deletedGroupID', :'eventCategoryID', jsonb_build_object(
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

-- Published ended event of the inactive community
select fx_event(
    :'inactiveCommunityEventID',
    :'inactiveCommunityGroupID',
    :'inactiveCommunityEventCategoryID',
    jsonb_build_object(
        'ends_at', current_timestamp - interval '2 days',
        'published', true,
        'starts_at', current_timestamp - interval '2 days 2 hours'
    )
);

-- Published ended event of the inactive group
select fx_event(:'inactiveGroupEventID', :'inactiveGroupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp - interval '2 days',
    'published', true,
    'starts_at', current_timestamp - interval '2 days 2 hours'
));

-- Unpublished event that already ended
select fx_event(:'unpublishedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp - interval '2 days',
    'published', false,
    'starts_at', current_timestamp - interval '2 days 2 hours'
));

-- Attendee of the public event with pending registration questions
insert into event_attendee (event_id, user_id, status)
values (:'eventID', :'pendingAttendeeID', 'registration-questions-pending');

-- Confirmed attendee of the public event
insert into event_attendee (event_id, user_id, status)
values (:'eventID', :'respondentID', 'confirmed');

-- Confirmed attendee of the public event without a response
insert into event_attendee (event_id, user_id, status)
values (:'eventID', :'unansweredAttendeeID', 'confirmed');

-- Ready survey of the canceled event
insert into event_survey (event_survey_id, event_id, status, title)
values (:'canceledEventSurveyID', :'canceledEventID', 'ready', 'Canceled event survey');

-- Ready survey closed manually on the public event
insert into event_survey (event_survey_id, event_id, status, title, closed_at)
values (:'closedSurveyID', :'eventID', 'ready', 'Closed survey', current_timestamp - interval '1 hour');

-- Ready survey of the event without dates
insert into event_survey (event_survey_id, event_id, status, title)
values (:'datelessEventSurveyID', :'datelessEventID', 'ready', 'Dateless event survey');

-- Ready survey of the deleted event
insert into event_survey (event_survey_id, event_id, status, title)
values (:'deletedEventSurveyID', :'deletedEventID', 'ready', 'Deleted event survey');

-- Ready survey of the deleted group event
insert into event_survey (event_survey_id, event_id, status, title)
values (:'deletedGroupSurveyID', :'deletedGroupEventID', 'ready', 'Deleted group survey');

-- Draft survey of the public event
insert into event_survey (event_survey_id, event_id, status, title)
values (:'draftSurveyID', :'eventID', 'draft', 'Draft survey');

-- Ready survey of the inactive community event
insert into event_survey (event_survey_id, event_id, status, title)
values (:'inactiveCommunitySurveyID', :'inactiveCommunityEventID', 'ready', 'Inactive community survey');

-- Ready survey of the inactive group event
insert into event_survey (event_survey_id, event_id, status, title)
values (:'inactiveGroupSurveyID', :'inactiveGroupEventID', 'ready', 'Inactive group survey');

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

-- Ready survey whose custom opening is in the future
insert into event_survey (event_survey_id, event_id, status, title, opens_at)
values (:'scheduledSurveyID', :'eventID', 'ready', 'Scheduled survey', current_timestamp + interval '1 day');

-- Ready survey of the unpublished event
insert into event_survey (event_survey_id, event_id, status, title)
values (:'unpublishedEventSurveyID', :'unpublishedEventID', 'ready', 'Unpublished event survey');

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

-- Should return null for closed surveys
select is(
    get_user_event_survey(:'closedSurveyID'::uuid, :'respondentID'::uuid)::jsonb,
    null,
    'Should return null for closed surveys'
);

-- Should return null for draft surveys
select is(
    get_user_event_survey(:'draftSurveyID'::uuid, :'respondentID'::uuid)::jsonb,
    null,
    'Should return null for draft surveys'
);

-- Should return null for non-confirmed attendees
select is(
    get_user_event_survey(:'openSurveyID'::uuid, :'pendingAttendeeID'::uuid)::jsonb,
    null,
    'Should return null for non-confirmed attendees'
);

-- Should return null for scheduled surveys
select is(
    get_user_event_survey(:'scheduledSurveyID'::uuid, :'respondentID'::uuid)::jsonb,
    null,
    'Should return null for scheduled surveys'
);

-- Should return null for surveys of canceled events
select is(
    get_user_event_survey(:'canceledEventSurveyID'::uuid, :'respondentID'::uuid)::jsonb,
    null,
    'Should return null for surveys of canceled events'
);

-- Should return null for surveys of deleted events
select is(
    get_user_event_survey(:'deletedEventSurveyID'::uuid, :'respondentID'::uuid)::jsonb,
    null,
    'Should return null for surveys of deleted events'
);

-- Should return null for surveys of deleted groups
select is(
    get_user_event_survey(:'deletedGroupSurveyID'::uuid, :'respondentID'::uuid)::jsonb,
    null,
    'Should return null for surveys of deleted groups'
);

-- Should return null for surveys of events without dates
select is(
    get_user_event_survey(:'datelessEventSurveyID'::uuid, :'respondentID'::uuid)::jsonb,
    null,
    'Should return null for surveys of events without dates'
);

-- Should return null for surveys of inactive communities
select is(
    get_user_event_survey(:'inactiveCommunitySurveyID'::uuid, :'respondentID'::uuid)::jsonb,
    null,
    'Should return null for surveys of inactive communities'
);

-- Should return null for surveys of inactive groups
select is(
    get_user_event_survey(:'inactiveGroupSurveyID'::uuid, :'respondentID'::uuid)::jsonb,
    null,
    'Should return null for surveys of inactive groups'
);

-- Should return null for surveys of unpublished events
select is(
    get_user_event_survey(:'unpublishedEventSurveyID'::uuid, :'respondentID'::uuid)::jsonb,
    null,
    'Should return null for surveys of unpublished events'
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
        'title', 'Open survey',

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
