-- Tests resolving the live state of a survey.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(13);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set closedManuallySurveyID 'a5e00006-0000-0000-0000-000000000001'
\set closingNowSurveyID 'a5e00006-0000-0000-0000-000000000012'
\set closingPassedSurveyID 'a5e00006-0000-0000-0000-000000000002'
\set communityID 'a5e00006-0000-0000-0000-000000000003'
\set datelessEventID 'a5e00006-0000-0000-0000-000000000004'
\set datelessSurveyID 'a5e00006-0000-0000-0000-000000000005'
\set draftClosingPassedSurveyID 'a5e00006-0000-0000-0000-000000000013'
\set draftSurveyID 'a5e00006-0000-0000-0000-000000000006'
\set endedEventID 'a5e00006-0000-0000-0000-000000000007'
\set eventCategoryID 'a5e00006-0000-0000-0000-000000000008'
\set futureOpeningSurveyID 'a5e00006-0000-0000-0000-000000000009'
\set groupCategoryID 'a5e00006-0000-0000-0000-00000000000a'
\set groupID 'a5e00006-0000-0000-0000-00000000000b'
\set justOpenedSurveyID 'a5e00006-0000-0000-0000-000000000014'
\set noScheduleSurveyID 'a5e00006-0000-0000-0000-000000000015'
\set openSurveyID 'a5e00006-0000-0000-0000-00000000000c'
\set unpublishedEventID 'a5e00006-0000-0000-0000-00000000000d'
\set unpublishedSurveyID 'a5e00006-0000-0000-0000-00000000000e'
\set upcomingClosedSurveyID 'a5e00006-0000-0000-0000-00000000000f'
\set upcomingEventID 'a5e00006-0000-0000-0000-000000000010'
\set upcomingSurveyID 'a5e00006-0000-0000-0000-000000000011'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community hosting the surveyed events
select fx_community(:'communityID');

-- Event category used by the surveyed events
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category used by the surveyed events group
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group hosting the surveyed events
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Published event without dates
select fx_event(:'datelessEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true
));

-- Published event that already ended
select fx_event(:'endedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp - interval '1 day',
    'published', true,
    'starts_at', current_timestamp - interval '1 day 2 hours'
));

-- Published event that has not started yet
select fx_event(:'upcomingEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp + interval '1 day 2 hours',
    'published', true,
    'starts_at', current_timestamp + interval '1 day'
));

-- Unpublished event that already ended
select fx_event(:'unpublishedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp - interval '1 day',
    'starts_at', current_timestamp - interval '1 day 2 hours'
));

-- Ready survey closed manually after the event
insert into event_survey (event_survey_id, event_id, status, title, closed_at)
values (:'closedManuallySurveyID', :'endedEventID', 'ready', 'Closed manually', current_timestamp - interval '1 hour');

-- Ready survey closing exactly now
insert into event_survey (event_survey_id, event_id, status, title, closes_at)
values (:'closingNowSurveyID', :'endedEventID', 'ready', 'Closing now', current_timestamp);

-- Ready survey whose closing date passed
insert into event_survey (event_survey_id, event_id, status, title, closes_at)
values (:'closingPassedSurveyID', :'endedEventID', 'ready', 'Closing passed', current_timestamp - interval '1 hour');

-- Ready survey on the event without dates
insert into event_survey (event_survey_id, event_id, status, title)
values (:'datelessSurveyID', :'datelessEventID', 'ready', 'Dateless');

-- Draft survey whose closing date passed
insert into event_survey (event_survey_id, event_id, status, title, closes_at)
values (:'draftClosingPassedSurveyID', :'endedEventID', 'draft', 'Draft closing passed', current_timestamp - interval '1 hour');

-- Draft survey on the ended event
insert into event_survey (event_survey_id, event_id, status, title)
values (:'draftSurveyID', :'endedEventID', 'draft', 'Draft');

-- Ready survey whose custom opening is in the future
insert into event_survey (event_survey_id, event_id, status, title, opens_at)
values (:'futureOpeningSurveyID', :'endedEventID', 'ready', 'Future opening', current_timestamp + interval '1 day');

-- Ready survey whose custom opening is exactly now
insert into event_survey (event_survey_id, event_id, status, title, opens_at)
values (:'justOpenedSurveyID', :'endedEventID', 'ready', 'Just opened', current_timestamp);

-- Ready survey without dates on the ended event
insert into event_survey (event_survey_id, event_id, status, title)
values (:'noScheduleSurveyID', :'endedEventID', 'ready', 'No schedule');

-- Ready survey open until a future closing date
insert into event_survey (event_survey_id, event_id, status, title, closes_at)
values (:'openSurveyID', :'endedEventID', 'ready', 'Open', current_timestamp + interval '1 day');

-- Ready survey closed manually before the event ends
insert into event_survey (event_survey_id, event_id, status, title, closed_at)
values (:'upcomingClosedSurveyID', :'upcomingEventID', 'ready', 'Upcoming closed', current_timestamp - interval '1 hour');

-- Ready survey waiting for the event to end
insert into event_survey (event_survey_id, event_id, status, title)
values (:'upcomingSurveyID', :'upcomingEventID', 'ready', 'Upcoming');

-- Ready survey on the unpublished event
insert into event_survey (event_survey_id, event_id, status, title)
values (:'unpublishedSurveyID', :'unpublishedEventID', 'ready', 'Unpublished');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should report closed surveys before their event ends
select is(
    (
        select event_survey_state(s, e)
        from event_survey s
        join event e on e.event_id = s.event_id
        where s.event_survey_id = :'upcomingClosedSurveyID'
    ),
    'closed',
    'Should report closed surveys before their event ends'
);

-- Should report draft surveys as draft
select is(
    (
        select event_survey_state(s, e)
        from event_survey s
        join event e on e.event_id = s.event_id
        where s.event_survey_id = :'draftSurveyID'
    ),
    'draft',
    'Should report draft surveys as draft'
);

-- Should report draft surveys past their closing date as draft
select is(
    (
        select event_survey_state(s, e)
        from event_survey s
        join event e on e.event_id = s.event_id
        where s.event_survey_id = :'draftClosingPassedSurveyID'
    ),
    'draft',
    'Should report draft surveys past their closing date as draft'
);

-- Should report manually closed surveys as closed
select is(
    (
        select event_survey_state(s, e)
        from event_survey s
        join event e on e.event_id = s.event_id
        where s.event_survey_id = :'closedManuallySurveyID'
    ),
    'closed',
    'Should report manually closed surveys as closed'
);

-- Should report ready surveys after the event ends as open
select is(
    (
        select event_survey_state(s, e)
        from event_survey s
        join event e on e.event_id = s.event_id
        where s.event_survey_id = :'openSurveyID'
    ),
    'open',
    'Should report ready surveys after the event ends as open'
);

-- Should report ready surveys of ended events without survey dates as open
select is(
    (
        select event_survey_state(s, e)
        from event_survey s
        join event e on e.event_id = s.event_id
        where s.event_survey_id = :'noScheduleSurveyID'
    ),
    'open',
    'Should report ready surveys of ended events without survey dates as open'
);

-- Should report surveys closing exactly now as closed
select is(
    (
        select event_survey_state(s, e)
        from event_survey s
        join event e on e.event_id = s.event_id
        where s.event_survey_id = :'closingNowSurveyID'
    ),
    'closed',
    'Should report surveys closing exactly now as closed'
);

-- Should report surveys of events without dates as scheduled
select is(
    (
        select event_survey_state(s, e)
        from event_survey s
        join event e on e.event_id = s.event_id
        where s.event_survey_id = :'datelessSurveyID'
    ),
    'scheduled',
    'Should report surveys of events without dates as scheduled'
);

-- Should report surveys of unpublished events as scheduled
select is(
    (
        select event_survey_state(s, e)
        from event_survey s
        join event e on e.event_id = s.event_id
        where s.event_survey_id = :'unpublishedSurveyID'
    ),
    'scheduled',
    'Should report surveys of unpublished events as scheduled'
);

-- Should report surveys of upcoming events as scheduled
select is(
    (
        select event_survey_state(s, e)
        from event_survey s
        join event e on e.event_id = s.event_id
        where s.event_survey_id = :'upcomingSurveyID'
    ),
    'scheduled',
    'Should report surveys of upcoming events as scheduled'
);

-- Should report surveys opening exactly now as open
select is(
    (
        select event_survey_state(s, e)
        from event_survey s
        join event e on e.event_id = s.event_id
        where s.event_survey_id = :'justOpenedSurveyID'
    ),
    'open',
    'Should report surveys opening exactly now as open'
);

-- Should report surveys past their closing date as closed
select is(
    (
        select event_survey_state(s, e)
        from event_survey s
        join event e on e.event_id = s.event_id
        where s.event_survey_id = :'closingPassedSurveyID'
    ),
    'closed',
    'Should report surveys past their closing date as closed'
);

-- Should report surveys with a future custom opening as scheduled
select is(
    (
        select event_survey_state(s, e)
        from event_survey s
        join event e on e.event_id = s.event_id
        where s.event_survey_id = :'futureOpeningSurveyID'
    ),
    'scheduled',
    'Should report surveys with a future custom opening as scheduled'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
