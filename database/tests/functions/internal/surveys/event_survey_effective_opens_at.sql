-- Tests resolving when a survey opens.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'a5e00005-0000-0000-0000-000000000001'
\set datelessEventID 'a5e00005-0000-0000-0000-000000000002'
\set datelessSurveyID 'a5e00005-0000-0000-0000-000000000003'
\set earlyOpeningSurveyID 'a5e00005-0000-0000-0000-000000000004'
\set eventCategoryID 'a5e00005-0000-0000-0000-000000000005'
\set eventID 'a5e00005-0000-0000-0000-000000000006'
\set groupCategoryID 'a5e00005-0000-0000-0000-000000000007'
\set groupID 'a5e00005-0000-0000-0000-000000000008'
\set lateOpeningSurveyID 'a5e00005-0000-0000-0000-000000000009'
\set noOpeningSurveyID 'a5e00005-0000-0000-0000-00000000000a'
\set startOnlyEventID 'a5e00005-0000-0000-0000-00000000000b'
\set startOnlyLateOpeningSurveyID 'a5e00005-0000-0000-0000-00000000000d'
\set startOnlySurveyID 'a5e00005-0000-0000-0000-00000000000c'

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

-- Event with a start and an end
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', '2030-01-01 12:00:00+00',
    'starts_at', '2030-01-01 10:00:00+00'
));

-- Event with a start only
select fx_event(:'startOnlyEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'starts_at', '2030-02-01 10:00:00+00'
));

-- Survey with a custom opening on the dateless event
insert into event_survey (event_survey_id, event_id, title, opens_at)
values (:'datelessSurveyID', :'datelessEventID', 'Dateless survey', '2030-03-01 10:00:00+00');

-- Survey whose custom opening precedes the event end
insert into event_survey (event_survey_id, event_id, title, opens_at)
values (:'earlyOpeningSurveyID', :'eventID', 'Early survey', '2030-01-01 11:00:00+00');

-- Survey whose custom opening follows the event end
insert into event_survey (event_survey_id, event_id, title, opens_at)
values (:'lateOpeningSurveyID', :'eventID', 'Late survey', '2030-01-02 09:00:00+00');

-- Survey without a custom opening
insert into event_survey (event_survey_id, event_id, title)
values (:'noOpeningSurveyID', :'eventID', 'Survey');

-- Survey whose custom opening follows the start of the start-only event
insert into event_survey (event_survey_id, event_id, title, opens_at)
values (:'startOnlyLateOpeningSurveyID', :'startOnlyEventID', 'Start only late survey', '2030-02-02 09:00:00+00');

-- Survey without a custom opening on the start-only event
insert into event_survey (event_survey_id, event_id, title)
values (:'startOnlySurveyID', :'startOnlyEventID', 'Start only survey');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should fall back to the event start when the event has no end
select is(
    (
        select event_survey_effective_opens_at(s, e)
        from event_survey s
        join event e on e.event_id = s.event_id
        where s.event_survey_id = :'startOnlySurveyID'
    ),
    '2030-02-01 10:00:00+00'::timestamptz,
    'Should fall back to the event start when the event has no end'
);

-- Should never open before the event ends
select is(
    (
        select event_survey_effective_opens_at(s, e)
        from event_survey s
        join event e on e.event_id = s.event_id
        where s.event_survey_id = :'earlyOpeningSurveyID'
    ),
    '2030-01-01 12:00:00+00'::timestamptz,
    'Should never open before the event ends'
);

-- Should open at a custom opening after the event end
select is(
    (
        select event_survey_effective_opens_at(s, e)
        from event_survey s
        join event e on e.event_id = s.event_id
        where s.event_survey_id = :'lateOpeningSurveyID'
    ),
    '2030-01-02 09:00:00+00'::timestamptz,
    'Should open at a custom opening after the event end'
);

-- Should open at a custom opening after the start of an event without an end
select is(
    (
        select event_survey_effective_opens_at(s, e)
        from event_survey s
        join event e on e.event_id = s.event_id
        where s.event_survey_id = :'startOnlyLateOpeningSurveyID'
    ),
    '2030-02-02 09:00:00+00'::timestamptz,
    'Should open at a custom opening after the start of an event without an end'
);

-- Should open at the event end without a custom opening
select is(
    (
        select event_survey_effective_opens_at(s, e)
        from event_survey s
        join event e on e.event_id = s.event_id
        where s.event_survey_id = :'noOpeningSurveyID'
    ),
    '2030-01-01 12:00:00+00'::timestamptz,
    'Should open at the event end without a custom opening'
);

-- Should return null when the event has no dates
select is(
    (
        select event_survey_effective_opens_at(s, e)
        from event_survey s
        join event e on e.event_id = s.event_id
        where s.event_survey_id = :'datelessSurveyID'
    ),
    null::timestamptz,
    'Should return null when the event has no dates'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
