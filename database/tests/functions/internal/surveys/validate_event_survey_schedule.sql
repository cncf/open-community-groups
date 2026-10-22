-- Tests validating whether a survey can be ready.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'a5e00009-0000-0000-0000-000000000001'
\set datelessEventID 'a5e00009-0000-0000-0000-000000000002'
\set datelessSurveyID 'a5e00009-0000-0000-0000-000000000003'
\set earlyClosingSurveyID 'a5e00009-0000-0000-0000-000000000004'
\set endedEventID 'a5e00009-0000-0000-0000-000000000005'
\set eventCategoryID 'a5e00009-0000-0000-0000-000000000006'
\set eventEndClosingSurveyID 'a5e00009-0000-0000-0000-000000000013'
\set groupCategoryID 'a5e00009-0000-0000-0000-000000000007'
\set groupID 'a5e00009-0000-0000-0000-000000000008'
\set noClosingSurveyID 'a5e00009-0000-0000-0000-000000000009'
\set noQuestionsSurveyID 'a5e00009-0000-0000-0000-00000000000a'
\set nowClosingSurveyID 'a5e00009-0000-0000-0000-000000000015'
\set pastClosingSurveyID 'a5e00009-0000-0000-0000-00000000000b'
\set upcomingEventID 'a5e00009-0000-0000-0000-00000000000c'
\set validSurveyID 'a5e00009-0000-0000-0000-00000000000d'

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

-- Event without dates
select fx_event(:'datelessEventID', :'groupID', :'eventCategoryID');

-- Event that already ended
select fx_event(:'endedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp - interval '1 day',
    'starts_at', current_timestamp - interval '1 day 2 hours'
));

-- Event ending in two days
select fx_event(:'upcomingEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp + interval '2 days',
    'starts_at', current_timestamp + interval '1 day'
));

-- Survey closing in the future on the event without dates
insert into event_survey (event_survey_id, event_id, questions, title, closes_at)
values (
    :'datelessSurveyID',
    :'datelessEventID',
    '[{"id": "a5e00009-0000-0000-0000-00000000000e", "kind": "free-text", "prompt": "Feedback", "required": false}]',
    'Dateless survey',
    current_timestamp + interval '1 day'
);

-- Survey closing before its event ends
insert into event_survey (event_survey_id, event_id, questions, title, closes_at)
values (
    :'earlyClosingSurveyID',
    :'upcomingEventID',
    '[{"id": "a5e00009-0000-0000-0000-00000000000f", "kind": "free-text", "prompt": "Feedback", "required": false}]',
    'Early closing survey',
    current_timestamp + interval '1 day'
);

-- Survey closing exactly when its event ends
insert into event_survey (event_survey_id, event_id, questions, title, closes_at)
values (
    :'eventEndClosingSurveyID',
    :'upcomingEventID',
    '[{"id": "a5e00009-0000-0000-0000-000000000014", "kind": "free-text", "prompt": "Feedback", "required": false}]',
    'Event end closing survey',
    current_timestamp + interval '2 days'
);

-- Survey without a closing date
insert into event_survey (event_survey_id, event_id, questions, title)
values (
    :'noClosingSurveyID',
    :'endedEventID',
    '[{"id": "a5e00009-0000-0000-0000-000000000010", "kind": "free-text", "prompt": "Feedback", "required": false}]',
    'No closing survey'
);

-- Survey without questions
insert into event_survey (event_survey_id, event_id, title)
values (:'noQuestionsSurveyID', :'endedEventID', 'No questions survey');

-- Survey closing exactly now
insert into event_survey (event_survey_id, event_id, questions, title, closes_at)
values (
    :'nowClosingSurveyID',
    :'endedEventID',
    '[{"id": "a5e00009-0000-0000-0000-000000000016", "kind": "free-text", "prompt": "Feedback", "required": false}]',
    'Now closing survey',
    current_timestamp
);

-- Survey whose closing date already passed
insert into event_survey (event_survey_id, event_id, questions, title, closes_at)
values (
    :'pastClosingSurveyID',
    :'endedEventID',
    '[{"id": "a5e00009-0000-0000-0000-000000000011", "kind": "free-text", "prompt": "Feedback", "required": false}]',
    'Past closing survey',
    current_timestamp - interval '1 hour'
);

-- Survey closing after its event ends
insert into event_survey (event_survey_id, event_id, questions, title, closes_at)
values (
    :'validSurveyID',
    :'upcomingEventID',
    '[{"id": "a5e00009-0000-0000-0000-000000000012", "kind": "free-text", "prompt": "Feedback", "required": false}]',
    'Valid survey',
    current_timestamp + interval '3 days'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept closing dates after the event ends
select lives_ok(
    format(
        $$
            select validate_event_survey_schedule(s, e)
            from event_survey s
            join event e on e.event_id = s.event_id
            where s.event_survey_id = %L::uuid
        $$,
        :'validSurveyID'
    ),
    'Should accept closing dates after the event ends'
);

-- Should accept future closing dates on events without dates
select lives_ok(
    format(
        $$
            select validate_event_survey_schedule(s, e)
            from event_survey s
            join event e on e.event_id = s.event_id
            where s.event_survey_id = %L::uuid
        $$,
        :'datelessSurveyID'
    ),
    'Should accept future closing dates on events without dates'
);

-- Should accept surveys without a closing date
select lives_ok(
    format(
        $$
            select validate_event_survey_schedule(s, e)
            from event_survey s
            join event e on e.event_id = s.event_id
            where s.event_survey_id = %L::uuid
        $$,
        :'noClosingSurveyID'
    ),
    'Should accept surveys without a closing date'
);

-- Should reject closing dates at the event end
select throws_ok(
    format(
        $$
            select validate_event_survey_schedule(s, e)
            from event_survey s
            join event e on e.event_id = s.event_id
            where s.event_survey_id = %L::uuid
        $$,
        :'eventEndClosingSurveyID'
    ),
    'OCG01',
    'event survey closing date must be after the survey opens',
    'Should reject closing dates at the event end'
);

-- Should reject closing dates before the survey opens
select throws_ok(
    format(
        $$
            select validate_event_survey_schedule(s, e)
            from event_survey s
            join event e on e.event_id = s.event_id
            where s.event_survey_id = %L::uuid
        $$,
        :'earlyClosingSurveyID'
    ),
    'OCG01',
    'event survey closing date must be after the survey opens',
    'Should reject closing dates before the survey opens'
);

-- Should reject closing dates exactly now
select throws_ok(
    format(
        $$
            select validate_event_survey_schedule(s, e)
            from event_survey s
            join event e on e.event_id = s.event_id
            where s.event_survey_id = %L::uuid
        $$,
        :'nowClosingSurveyID'
    ),
    'OCG01',
    'event survey closing date must be in the future',
    'Should reject closing dates exactly now'
);

-- Should reject closing dates in the past
select throws_ok(
    format(
        $$
            select validate_event_survey_schedule(s, e)
            from event_survey s
            join event e on e.event_id = s.event_id
            where s.event_survey_id = %L::uuid
        $$,
        :'pastClosingSurveyID'
    ),
    'OCG01',
    'event survey closing date must be in the future',
    'Should reject closing dates in the past'
);

-- Should reject surveys without questions
select throws_ok(
    format(
        $$
            select validate_event_survey_schedule(s, e)
            from event_survey s
            join event e on e.event_id = s.event_id
            where s.event_survey_id = %L::uuid
        $$,
        :'noQuestionsSurveyID'
    ),
    'OCG01',
    'event survey must have at least one question',
    'Should reject surveys without questions'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
