-- Tests enqueuing the opening emails of due event surveys.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set alreadyProcessedSurveyID 'a5e00036-0000-0000-0000-000000000001'
\set checkedInSurveyID 'a5e00036-0000-0000-0000-000000000004'
\set closedSurveyID 'a5e00036-0000-0000-0000-000000000006'
\set communityID 'a5e00036-0000-0000-0000-000000000007'
\set draftSurveyID 'a5e00036-0000-0000-0000-00000000000d'
\set dueSurveyID 'a5e00036-0000-0000-0000-00000000000e'
\set eventCategoryID 'a5e00036-0000-0000-0000-00000000000f'
\set eventID 'a5e00036-0000-0000-0000-000000000010'
\set groupCategoryID 'a5e00036-0000-0000-0000-000000000011'
\set groupID 'a5e00036-0000-0000-0000-000000000012'
\set inactiveCommunityEventCategoryID 'a5e00036-0000-0000-0000-000000000013'
\set inactiveCommunityEventID 'a5e00036-0000-0000-0000-000000000014'
\set inactiveCommunityGroupCategoryID 'a5e00036-0000-0000-0000-000000000015'
\set inactiveCommunityGroupID 'a5e00036-0000-0000-0000-000000000016'
\set inactiveCommunityID 'a5e00036-0000-0000-0000-000000000017'
\set inactiveCommunitySurveyID 'a5e00036-0000-0000-0000-000000000018'
\set noRecipientsEventID 'a5e00036-0000-0000-0000-00000000001c'
\set noRecipientsSurveyID 'a5e00036-0000-0000-0000-00000000001d'
\set optedOutAttendeeID 'a5e00036-0000-0000-0000-00000000001e'
\set siteID 'a5e00036-0000-0000-0000-000000000020'
\set skippedAttendeeID 'a5e00036-0000-0000-0000-000000000021'
\set testEventID 'a5e00036-0000-0000-0000-000000000022'
\set testEventSurveyID 'a5e00036-0000-0000-0000-000000000023'
\set unverifiedAttendeeID 'a5e00036-0000-0000-0000-000000000026'
\set upcomingEventID 'a5e00036-0000-0000-0000-000000000027'
\set upcomingEventSurveyID 'a5e00036-0000-0000-0000-000000000028'
\set verifiedAttendeeID 'a5e00036-0000-0000-0000-000000000029'
\set verifiedNotCheckedInID 'a5e00036-0000-0000-0000-00000000002a'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Active community hosting the surveyed events
select fx_community(:'communityID', jsonb_build_object(
    'active', true,
    'name', 'survey-emails-community'
));

-- Inactive community hosting a skipped survey
select fx_community(:'inactiveCommunityID', jsonb_build_object('active', false));

-- Site whose theme the opening email carries
insert into site (site_id, description, theme, title)
values (:'siteID', 'Survey emails site', '{"primary_color": "#2563eb"}'::jsonb, 'Survey emails site');

-- Verified attendee who opted out of survey emails
select fx_user(:'optedOutAttendeeID', jsonb_build_object('email_verified', true));

-- Verified attendee of the inactive-community and not-ended events
select fx_user(:'skippedAttendeeID', jsonb_build_object('email_verified', true));

-- Checked-in attendee without a verified email
select fx_user(:'unverifiedAttendeeID', jsonb_build_object('email_verified', false));

-- Verified checked-in attendee of the due event and the test event
select fx_user(:'verifiedAttendeeID', jsonb_build_object('email_verified', true));

-- Verified attendee of the due event who did not check in
select fx_user(:'verifiedNotCheckedInID', jsonb_build_object('email_verified', true));

-- Event category of the active community
select fx_event_category(:'eventCategoryID', :'communityID');

-- Event category of the inactive community
select fx_event_category(:'inactiveCommunityEventCategoryID', :'inactiveCommunityID');

-- Group category of the active community
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group category of the inactive community
select fx_group_category(:'inactiveCommunityGroupCategoryID', :'inactiveCommunityID');

-- Opt-out of the survey emails category
insert into user_notification_opt_out (notification_category_id, user_id)
values ('event-surveys', :'optedOutAttendeeID');

-- Active group hosting the surveyed events
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', true,
    'slug', 'survey-emails-group-x1y2',
    'slug_pretty', 'survey-emails-group'
));

-- Active group of the inactive community
select fx_group(
    :'inactiveCommunityGroupID',
    :'inactiveCommunityID',
    :'inactiveCommunityGroupCategoryID',
    jsonb_build_object('active', true)
);

-- Published ended event whose surveys are due
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp - interval '2 days',
    'published', true,
    'slug', 'survey-emails-event',
    'starts_at', current_timestamp - interval '2 days 2 hours',
    'test_event', false
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

-- Published ended event without verified attendees
select fx_event(:'noRecipientsEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp - interval '2 days',
    'published', true,
    'starts_at', current_timestamp - interval '2 days 2 hours',
    'test_event', false
));

-- Published ended test event
select fx_event(:'testEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp - interval '2 days',
    'published', true,
    'starts_at', current_timestamp - interval '2 days 2 hours',
    'test_event', true
));

-- Published event that has not ended yet
select fx_event(:'upcomingEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp + interval '1 day 2 hours',
    'published', true,
    'starts_at', current_timestamp + interval '1 day'
));

-- Confirmed attendees of the due event
insert into event_attendee (checked_in, event_id, status, user_id)
values
    (false, :'eventID', 'confirmed', :'optedOutAttendeeID'),
    (true, :'eventID', 'confirmed', :'unverifiedAttendeeID'),
    (true, :'eventID', 'confirmed', :'verifiedAttendeeID'),
    (false, :'eventID', 'confirmed', :'verifiedNotCheckedInID');

-- Unverified confirmed attendee of the event without recipients
insert into event_attendee (checked_in, event_id, status, user_id)
values (false, :'noRecipientsEventID', 'confirmed', :'unverifiedAttendeeID');

-- Verified confirmed attendee of the inactive-community and not-ended events
insert into event_attendee (checked_in, event_id, status, user_id)
select true, event_id, 'confirmed', :'skippedAttendeeID'
from unnest(array[
    :'inactiveCommunityEventID',
    :'upcomingEventID'
]::uuid[]) as event_id;

-- Verified confirmed attendee of the test event
insert into event_attendee (checked_in, event_id, status, user_id)
values (true, :'testEventID', 'confirmed', :'verifiedAttendeeID');

-- Open survey whose opening email was already handled
insert into event_survey (
    event_survey_id,
    event_id,
    status,
    title,

    open_notification_processed_at,
    open_notification_recipients
) values (
    :'alreadyProcessedSurveyID',
    :'eventID',
    'ready',
    'Already processed survey',

    current_timestamp - interval '1 day',
    7
);

-- Open anonymous survey limited to checked-in attendees
insert into event_survey (event_survey_id, anonymous, audience, event_id, status, title)
values (:'checkedInSurveyID', true, 'checked-in', :'eventID', 'ready', 'Checked-in survey');

-- Ready survey closed manually
insert into event_survey (event_survey_id, event_id, status, title, closed_at)
values (:'closedSurveyID', :'eventID', 'ready', 'Closed survey', current_timestamp - interval '1 hour');

-- Draft survey of the due event
insert into event_survey (event_survey_id, event_id, status, title)
values (:'draftSurveyID', :'eventID', 'draft', 'Draft survey');

-- Open identified survey with a closing date
insert into event_survey (event_survey_id, anonymous, audience, event_id, status, title, closes_at)
values (
    :'dueSurveyID',
    false,
    'confirmed',
    :'eventID',
    'ready',
    'Due survey',
    current_timestamp + interval '5 days'
);

-- Ready survey of the inactive community event
insert into event_survey (event_survey_id, event_id, status, title)
values (:'inactiveCommunitySurveyID', :'inactiveCommunityEventID', 'ready', 'Inactive community survey');

-- Open survey of the event without verified attendees
insert into event_survey (event_survey_id, event_id, status, title)
values (:'noRecipientsSurveyID', :'noRecipientsEventID', 'ready', 'No recipients survey');

-- Open survey of the test event
insert into event_survey (event_survey_id, event_id, status, title)
values (:'testEventSurveyID', :'testEventID', 'ready', 'Test event survey');

-- Ready survey of the event that has not ended
insert into event_survey (event_survey_id, event_id, status, title)
values (:'upcomingEventSurveyID', :'upcomingEventID', 'ready', 'Upcoming event survey');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return the number of notifications enqueued
select is(
    enqueue_due_event_survey_notifications(),
    3,
    'Should return the number of notifications enqueued'
);

-- Should build the template data of the opening email
select is(
    (
        select ntd.data
        from notification n
        join notification_template_data ntd using (notification_template_data_id)
        where n.kind = 'event-survey-opened'
        and n.user_id = :'verifiedNotCheckedInID'
    ),
    jsonb_build_object(
        'anonymous', false,
        'event', get_event_summary(:'communityID'::uuid, :'groupID'::uuid, :'eventID'::uuid)::jsonb,
        'link', '/dashboard/user?tab=surveys&event_survey_id=' || :'dueSurveyID',
        'survey_title', 'Due survey',
        'theme', '{"primary_color": "#2563eb"}'::jsonb,

        'closes_at', epoch_seconds(current_timestamp + interval '5 days')
    ),
    'Should build the template data of the opening email'
);

-- Should email the verified eligible attendees who accept survey emails
select results_eq(
    $$
        select ntd.data->>'survey_title', n.user_id
        from notification n
        join notification_template_data ntd using (notification_template_data_id)
        where n.kind = 'event-survey-opened'
        order by 1, 2
    $$,
    format(
        $$ values
            ('Checked-in survey', %L::uuid),
            ('Due survey', %L::uuid),
            ('Due survey', %L::uuid)
        $$,
        :'verifiedAttendeeID',
        :'verifiedAttendeeID',
        :'verifiedNotCheckedInID'
    ),
    'Should email the verified eligible attendees who accept survey emails'
);

-- Should enqueue nothing when run again
select is(
    enqueue_due_event_survey_notifications(),
    0,
    'Should enqueue nothing when run again'
);

-- Should keep the marker of surveys already processed
select is(
    (
        select jsonb_build_object(
            'open_notification_processed_at', s.open_notification_processed_at,
            'open_notification_recipients', s.open_notification_recipients
        )
        from event_survey s
        where s.event_survey_id = :'alreadyProcessedSurveyID'
    ),
    jsonb_build_object(
        'open_notification_processed_at', current_timestamp - interval '1 day',
        'open_notification_recipients', 7
    ),
    'Should keep the marker of surveys already processed'
);

-- Should leave closed, draft, inactive-community and not-ended surveys unprocessed
select results_eq(
    format(
        $$
            select
                s.event_survey_id,
                s.open_notification_processed_at,
                s.open_notification_recipients
            from event_survey s
            where s.event_survey_id = any(array[%L, %L, %L, %L]::uuid[])
            order by s.title
        $$,
        :'closedSurveyID',
        :'draftSurveyID',
        :'inactiveCommunitySurveyID',
        :'upcomingEventSurveyID'
    ),
    format(
        $$ values
            (%L::uuid, null::timestamptz, null::int),
            (%L::uuid, null::timestamptz, null::int),
            (%L::uuid, null::timestamptz, null::int),
            (%L::uuid, null::timestamptz, null::int)
        $$,
        :'closedSurveyID',
        :'draftSurveyID',
        :'inactiveCommunitySurveyID',
        :'upcomingEventSurveyID'
    ),
    'Should leave closed, draft, inactive-community and not-ended surveys unprocessed'
);

-- Should mark due surveys processed with the notifications enqueued
select results_eq(
    format(
        $$
            select
                s.event_survey_id,
                s.open_notification_processed_at = current_timestamp,
                s.open_notification_recipients
            from event_survey s
            where s.event_survey_id = any(array[%L, %L, %L]::uuid[])
            order by s.title
        $$,
        :'checkedInSurveyID',
        :'dueSurveyID',
        :'noRecipientsSurveyID'
    ),
    format(
        $$ values
            (%L::uuid, true, 1),
            (%L::uuid, true, 2),
            (%L::uuid, true, 0)
        $$,
        :'checkedInSurveyID',
        :'dueSurveyID',
        :'noRecipientsSurveyID'
    ),
    'Should mark due surveys processed with the notifications enqueued'
);

-- Should mark test event surveys processed without emailing their attendees
select is(
    (
        select jsonb_build_object(
            'open_notification_processed_at', s.open_notification_processed_at,
            'open_notification_recipients', s.open_notification_recipients
        )
        from event_survey s
        where s.event_survey_id = :'testEventSurveyID'
    ),
    jsonb_build_object(
        'open_notification_processed_at', current_timestamp,
        'open_notification_recipients', 0
    ),
    'Should mark test event surveys processed without emailing their attendees'
);

-- Should omit the closing date from the template data when unset
select is(
    (
        select ntd.data ? 'closes_at'
        from notification n
        join notification_template_data ntd using (notification_template_data_id)
        where n.kind = 'event-survey-opened'
        and ntd.data->>'survey_title' = 'Checked-in survey'
    ),
    false,
    'Should omit the closing date from the template data when unset'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
