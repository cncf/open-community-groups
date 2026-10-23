-- Tests listing the surveys a user reaches from the dashboard.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set answeredSurveyID 'a5e00035-0000-0000-0000-000000000001'
\set busyEventID 'a5e00035-0000-0000-0000-000000000002'
\set canceledEventID 'a5e00035-0000-0000-0000-000000000003'
\set canceledEventSurveyID 'a5e00035-0000-0000-0000-000000000004'
\set checkedInSurveyID 'a5e00035-0000-0000-0000-000000000005'
\set closedSurveyID 'a5e00035-0000-0000-0000-000000000006'
\set closingSoonSurveyID 'a5e00035-0000-0000-0000-000000000007'
\set communityID 'a5e00035-0000-0000-0000-000000000008'
\set draftSurveyID 'a5e00035-0000-0000-0000-00000000000c'
\set earlierClosedSurveyID 'a5e00035-0000-0000-0000-000000000030'
\set earlierEventID 'a5e00035-0000-0000-0000-00000000000d'
\set eventCategoryID 'a5e00035-0000-0000-0000-00000000000e'
\set eventID 'a5e00035-0000-0000-0000-00000000000f'
\set groupCategoryID 'a5e00035-0000-0000-0000-000000000010'
\set groupID 'a5e00035-0000-0000-0000-000000000011'
\set hiddenSurveysAttendeeID 'a5e00035-0000-0000-0000-000000000026'
\set inactiveCommunityEventCategoryID 'a5e00035-0000-0000-0000-000000000012'
\set inactiveCommunityEventID 'a5e00035-0000-0000-0000-000000000013'
\set inactiveCommunityGroupCategoryID 'a5e00035-0000-0000-0000-000000000014'
\set inactiveCommunityGroupID 'a5e00035-0000-0000-0000-000000000015'
\set inactiveCommunityID 'a5e00035-0000-0000-0000-000000000016'
\set inactiveCommunitySurveyID 'a5e00035-0000-0000-0000-000000000017'
\set inactiveGroupEventID 'a5e00035-0000-0000-0000-000000000018'
\set inactiveGroupID 'a5e00035-0000-0000-0000-000000000019'
\set inactiveGroupSurveyID 'a5e00035-0000-0000-0000-00000000001a'
\set multiCommunityAttendeeID 'a5e00035-0000-0000-0000-000000000027'
\set openedEarlierSurveyID 'a5e00035-0000-0000-0000-00000000001b'
\set openedLaterSurveyID 'a5e00035-0000-0000-0000-00000000001c'
\set otherCommunityEventCategoryID 'a5e00035-0000-0000-0000-000000000028'
\set otherCommunityEventID 'a5e00035-0000-0000-0000-000000000029'
\set otherCommunityGroupCategoryID 'a5e00035-0000-0000-0000-00000000002a'
\set otherCommunityGroupID 'a5e00035-0000-0000-0000-00000000002b'
\set otherCommunityID 'a5e00035-0000-0000-0000-00000000002c'
\set otherCommunitySurveyID 'a5e00035-0000-0000-0000-00000000002d'
\set outsiderID 'a5e00035-0000-0000-0000-00000000001d'
\set pagerID 'a5e00035-0000-0000-0000-00000000001e'
\set pendingAttendeeID 'a5e00035-0000-0000-0000-00000000002e'
\set recentlyClosedSurveyID 'a5e00035-0000-0000-0000-00000000002f'
\set respondentID 'a5e00035-0000-0000-0000-00000000001f'
\set scheduledSurveyID 'a5e00035-0000-0000-0000-000000000020'
\set unpublishedEventID 'a5e00035-0000-0000-0000-000000000021'
\set unpublishedEventSurveyID 'a5e00035-0000-0000-0000-000000000022'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Active community hosting the surveyed events
select fx_community(:'communityID', jsonb_build_object(
    'active', true,
    'display_name', 'Survey Panel Community',
    'name', 'survey-panel-community'
));

-- Inactive community hosting a hidden survey
select fx_community(:'inactiveCommunityID', jsonb_build_object('active', false));

-- Second active community hosting a surveyed event
select fx_community(:'otherCommunityID', jsonb_build_object(
    'active', true,
    'name', 'survey-panel-other-community'
));

-- Confirmed attendee of only the canceled and unpublished events
select fx_user(:'hiddenSurveysAttendeeID');

-- Confirmed attendee of events in both active communities
select fx_user(:'multiCommunityAttendeeID');

-- User outside every survey audience
select fx_user(:'outsiderID');

-- Confirmed attendee of the busy event
select fx_user(:'pagerID');

-- Attendee with pending registration questions
select fx_user(:'pendingAttendeeID');

-- Confirmed attendee of every other surveyed event
select fx_user(:'respondentID');

-- Event category of the active community
select fx_event_category(:'eventCategoryID', :'communityID');

-- Event category of the inactive community
select fx_event_category(:'inactiveCommunityEventCategoryID', :'inactiveCommunityID');

-- Event category of the second active community
select fx_event_category(:'otherCommunityEventCategoryID', :'otherCommunityID');

-- Group category of the active community
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group category of the inactive community
select fx_group_category(:'inactiveCommunityGroupCategoryID', :'inactiveCommunityID');

-- Group category of the second active community
select fx_group_category(:'otherCommunityGroupCategoryID', :'otherCommunityID');

-- Active group hosting the public surveyed events
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', true,
    'name', 'Survey Panel Group',
    'slug', 'survey-panel-group-x1y2',
    'slug_pretty', 'survey-panel-group'
));

-- Active group of the inactive community
select fx_group(
    :'inactiveCommunityGroupID',
    :'inactiveCommunityID',
    :'inactiveCommunityGroupCategoryID',
    jsonb_build_object('active', true)
);

-- Inactive group of the active community
select fx_group(:'inactiveGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('active', false));

-- Active group of the second active community
select fx_group(
    :'otherCommunityGroupID',
    :'otherCommunityID',
    :'otherCommunityGroupCategoryID',
    jsonb_build_object(
        'active', true,
        'slug', 'survey-panel-other-group'
    )
);

-- Published ended event with more open surveys than the page size cap
select fx_event(:'busyEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp - interval '2 days',
    'published', true,
    'starts_at', current_timestamp - interval '2 days 2 hours'
));

-- Canceled published event that already ended
select fx_event(:'canceledEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'ends_at', current_timestamp - interval '2 days',
    'published', true,
    'starts_at', current_timestamp - interval '2 days 2 hours'
));

-- Published event that ended before the main event
select fx_event(:'earlierEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp - interval '3 days',
    'name', 'Earlier Survey Event',
    'published', true,
    'slug', 'earlier-survey-event',
    'starts_at', current_timestamp - interval '3 days 2 hours',
    'timezone', 'America/New_York'
));

-- Published ended event hosting most listed surveys
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp - interval '2 days',
    'name', 'Survey Panel Event',
    'published', true,
    'slug', 'survey-panel-event',
    'starts_at', current_timestamp - interval '2 days 2 hours',
    'timezone', 'Europe/Madrid'
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

-- Published ended event of the second active community
select fx_event(
    :'otherCommunityEventID',
    :'otherCommunityGroupID',
    :'otherCommunityEventCategoryID',
    jsonb_build_object(
        'ends_at', current_timestamp - interval '1 day',
        'published', true,
        'slug', 'survey-panel-other-event',
        'starts_at', current_timestamp - interval '1 day 2 hours'
    )
);

-- Unpublished event that already ended
select fx_event(:'unpublishedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp - interval '2 days',
    'published', false,
    'starts_at', current_timestamp - interval '2 days 2 hours'
));

-- Confirmed attendance at the canceled and unpublished events only
insert into event_attendee (checked_in, event_id, status, user_id)
select false, event_id, 'confirmed', :'hiddenSurveysAttendeeID'
from unnest(array[:'canceledEventID', :'unpublishedEventID']::uuid[]) as event_id;

-- Confirmed attendance at events of both active communities
insert into event_attendee (checked_in, event_id, status, user_id)
select false, event_id, 'confirmed', :'multiCommunityAttendeeID'
from unnest(array[:'earlierEventID', :'otherCommunityEventID']::uuid[]) as event_id;

-- Confirmed attendance of the pager at the busy event
insert into event_attendee (checked_in, event_id, status, user_id)
values (false, :'busyEventID', 'confirmed', :'pagerID');

-- Attendance at the main event with pending registration questions
insert into event_attendee (checked_in, event_id, status, user_id)
values (false, :'eventID', 'registration-questions-pending', :'pendingAttendeeID');

-- Confirmed attendance of the respondent, without check-in, at every other surveyed event
insert into event_attendee (checked_in, event_id, status, user_id)
select false, event_id, 'confirmed', :'respondentID'
from unnest(array[
    :'canceledEventID',
    :'earlierEventID',
    :'eventID',
    :'inactiveCommunityEventID',
    :'inactiveGroupEventID',
    :'unpublishedEventID'
]::uuid[]) as event_id;

-- Fifty-one open surveys of the busy event
insert into event_survey (event_id, status, title)
select :'busyEventID', 'ready', 'Busy survey ' || n
from generate_series(1, 51) as n;

-- Open survey the respondent answered, closing soon
insert into event_survey (event_survey_id, event_id, status, title, closes_at)
values (:'answeredSurveyID', :'eventID', 'ready', 'Answered survey', current_timestamp + interval '1 day');

-- Ready survey of the canceled event
insert into event_survey (event_survey_id, event_id, status, title)
values (:'canceledEventSurveyID', :'canceledEventID', 'ready', 'Canceled event survey');

-- Open survey limited to checked-in attendees
insert into event_survey (event_survey_id, audience, event_id, status, title)
values (:'checkedInSurveyID', 'checked-in', :'eventID', 'ready', 'Checked-in survey');

-- Ready survey closed manually
insert into event_survey (event_survey_id, event_id, status, title, closed_at)
values (:'closedSurveyID', :'eventID', 'ready', 'Closed survey', current_timestamp - interval '1 hour');

-- Open survey closing tomorrow
insert into event_survey (event_survey_id, event_id, status, title, closes_at)
values (:'closingSoonSurveyID', :'eventID', 'ready', 'Closing soon', current_timestamp + interval '1 day');

-- Draft survey of the main event
insert into event_survey (event_survey_id, event_id, status, title)
values (:'draftSurveyID', :'eventID', 'draft', 'Draft survey');

-- Survey the respondent answered, closed a day ago
insert into event_survey (event_survey_id, event_id, status, title, closed_at)
values (:'earlierClosedSurveyID', :'eventID', 'ready', 'Earlier closed', current_timestamp - interval '1 day');

-- Ready survey of the inactive community event
insert into event_survey (event_survey_id, event_id, status, title)
values (:'inactiveCommunitySurveyID', :'inactiveCommunityEventID', 'ready', 'Inactive community survey');

-- Ready survey of the inactive group event
insert into event_survey (event_survey_id, event_id, status, title)
values (:'inactiveGroupSurveyID', :'inactiveGroupEventID', 'ready', 'Inactive group survey');

-- Open survey without a closing date that opened when the earlier event ended
insert into event_survey (event_survey_id, event_id, status, title)
values (:'openedEarlierSurveyID', :'earlierEventID', 'ready', 'Opened earlier');

-- Open survey without a closing date that opened when the main event ended
insert into event_survey (event_survey_id, event_id, status, title)
values (:'openedLaterSurveyID', :'eventID', 'ready', 'Opened later');

-- Open survey without a closing date of the second active community event
insert into event_survey (event_survey_id, event_id, status, title)
values (:'otherCommunitySurveyID', :'otherCommunityEventID', 'ready', 'Other community survey');

-- Survey the respondent answered, closed an hour ago
insert into event_survey (event_survey_id, event_id, status, title, closed_at)
values (:'recentlyClosedSurveyID', :'eventID', 'ready', 'Recently closed', current_timestamp - interval '1 hour');

-- Ready survey whose custom opening is in the future
insert into event_survey (event_survey_id, event_id, status, title, opens_at)
values (:'scheduledSurveyID', :'eventID', 'ready', 'Scheduled survey', current_timestamp + interval '1 day');

-- Ready survey of the unpublished event
insert into event_survey (event_survey_id, event_id, status, title)
values (:'unpublishedEventSurveyID', :'unpublishedEventID', 'ready', 'Unpublished event survey');

-- Responses of the respondent to the answered open and closed surveys
insert into event_survey_response (answers, event_survey_id, user_id)
select '{"answers": []}'::jsonb, event_survey_id, :'respondentID'
from unnest(array[
    :'answeredSurveyID',
    :'earlierClosedSurveyID',
    :'recentlyClosedSurveyID'
]::uuid[]) as event_survey_id;

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should apply the requested offset
select is(
    jsonb_array_length(
        list_user_event_surveys(:'pagerID'::uuid, '{"limit": 5, "offset": 49}'::jsonb)::jsonb->'surveys'
    ),
    2,
    'Should apply the requested offset'
);

-- Should cap the page size at fifty
select is(
    jsonb_array_length(list_user_event_surveys(:'pagerID'::uuid, '{"limit": 100}'::jsonb)::jsonb->'surveys'),
    50,
    'Should cap the page size at fifty'
);

-- Should default the page size to ten
select is(
    jsonb_array_length(list_user_event_surveys(:'pagerID'::uuid, '{}'::jsonb)::jsonb->'surveys'),
    10,
    'Should default the page size to ten'
);

-- Should list open eligible surveys unanswered first, then answered closed surveys most recent first
select is(
    list_user_event_surveys(:'respondentID'::uuid, '{}'::jsonb)::jsonb,
    jsonb_build_object(
        'surveys', jsonb_build_array(
            jsonb_build_object(
                'answered', false,
                'event_name', 'Survey Panel Event',
                'event_survey_id', :'closingSoonSurveyID'::uuid,
                'group_name', 'Survey Panel Group',
                'state', 'open',
                'timezone', 'Europe/Madrid',
                'title', 'Closing soon',

                'closed_at', null,
                'closes_at', epoch_seconds(current_timestamp + interval '1 day')
            ),
            jsonb_build_object(
                'answered', false,
                'event_name', 'Earlier Survey Event',
                'event_survey_id', :'openedEarlierSurveyID'::uuid,
                'group_name', 'Survey Panel Group',
                'state', 'open',
                'timezone', 'America/New_York',
                'title', 'Opened earlier',

                'closed_at', null,
                'closes_at', null
            ),
            jsonb_build_object(
                'answered', false,
                'event_name', 'Survey Panel Event',
                'event_survey_id', :'openedLaterSurveyID'::uuid,
                'group_name', 'Survey Panel Group',
                'state', 'open',
                'timezone', 'Europe/Madrid',
                'title', 'Opened later',

                'closed_at', null,
                'closes_at', null
            ),
            jsonb_build_object(
                'answered', true,
                'event_name', 'Survey Panel Event',
                'event_survey_id', :'answeredSurveyID'::uuid,
                'group_name', 'Survey Panel Group',
                'state', 'open',
                'timezone', 'Europe/Madrid',
                'title', 'Answered survey',

                'closed_at', null,
                'closes_at', epoch_seconds(current_timestamp + interval '1 day')
            ),
            jsonb_build_object(
                'answered', true,
                'event_name', 'Survey Panel Event',
                'event_survey_id', :'recentlyClosedSurveyID'::uuid,
                'group_name', 'Survey Panel Group',
                'state', 'closed',
                'timezone', 'Europe/Madrid',
                'title', 'Recently closed',

                'closed_at', epoch_seconds(current_timestamp - interval '1 hour'),
                'closes_at', null
            ),
            jsonb_build_object(
                'answered', true,
                'event_name', 'Survey Panel Event',
                'event_survey_id', :'earlierClosedSurveyID'::uuid,
                'group_name', 'Survey Panel Group',
                'state', 'closed',
                'timezone', 'Europe/Madrid',
                'title', 'Earlier closed',

                'closed_at', epoch_seconds(current_timestamp - interval '1 day'),
                'closes_at', null
            )
        ),
        'total', 6
    ),
    'Should list open eligible surveys unanswered first, then answered closed surveys most recent first'
);

-- Should list open surveys across communities
select is(
    (
        select jsonb_build_object(
            'event_survey_ids', jsonb_path_query_array(p, '$.surveys[*].event_survey_id'),
            'total', p->'total'
        )
        from (select list_user_event_surveys(:'multiCommunityAttendeeID'::uuid, '{}'::jsonb)::jsonb as p) as page
    ),
    jsonb_build_object(
        'event_survey_ids', jsonb_build_array(:'openedEarlierSurveyID'::uuid, :'otherCommunitySurveyID'::uuid),
        'total', 2
    ),
    'Should list open surveys across communities'
);

-- Should report the total beyond the requested page
select is(
    (list_user_event_surveys(:'pagerID'::uuid, '{"limit": 1}'::jsonb)::jsonb->>'total')::int,
    51,
    'Should report the total beyond the requested page'
);

-- Should return an empty page for non-confirmed attendees
select is(
    list_user_event_surveys(:'pendingAttendeeID'::uuid, '{}'::jsonb)::jsonb,
    jsonb_build_object('surveys', '[]'::jsonb, 'total', 0),
    'Should return an empty page for non-confirmed attendees'
);

-- Should return an empty page for surveys outside the public scope
select is(
    list_user_event_surveys(:'hiddenSurveysAttendeeID'::uuid, '{}'::jsonb)::jsonb,
    jsonb_build_object('surveys', '[]'::jsonb, 'total', 0),
    'Should return an empty page for surveys outside the public scope'
);

-- Should return an empty page for users outside every audience
select is(
    list_user_event_surveys(:'outsiderID'::uuid, '{}'::jsonb)::jsonb,
    jsonb_build_object('surveys', '[]'::jsonb, 'total', 0),
    'Should return an empty page for users outside every audience'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
