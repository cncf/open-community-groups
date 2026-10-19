-- Tests updating the settings of surveys of group events.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(32);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorUserID 'a5e00014-0000-0000-0000-000000000001'
\set anonymityDraftSurveyID 'a5e00014-0000-0000-0000-000000000017'
\set answeredDatesSurveyID 'a5e00014-0000-0000-0000-000000000018'
\set answeredSurveyID 'a5e00014-0000-0000-0000-000000000002'
\set canceledEventID 'a5e00014-0000-0000-0000-000000000003'
\set canceledEventSurveyID 'a5e00014-0000-0000-0000-000000000004'
\set closedAnsweredSurveyID 'a5e00014-0000-0000-0000-000000000005'
\set communityID 'a5e00014-0000-0000-0000-000000000006'
\set configSurveyID 'a5e00014-0000-0000-0000-000000000007'
\set draftDatesSurveyID 'a5e00014-0000-0000-0000-000000000019'
\set draftSurveyID 'a5e00014-0000-0000-0000-000000000008'
\set eventCategoryID 'a5e00014-0000-0000-0000-000000000009'
\set eventID 'a5e00014-0000-0000-0000-00000000000a'
\set fractionalDatesSurveyID 'a5e00014-0000-0000-0000-00000000001a'
\set groupCategoryID 'a5e00014-0000-0000-0000-00000000000b'
\set groupID 'a5e00014-0000-0000-0000-00000000000c'
\set openAnonymousSurveyID 'a5e00014-0000-0000-0000-000000000013'
\set openIdentifiedSurveyID 'a5e00014-0000-0000-0000-000000000014'
\set otherEventID 'a5e00014-0000-0000-0000-00000000000d'
\set otherEventSurveyID 'a5e00014-0000-0000-0000-00000000000e'
\set processedAnonymousSurveyID 'a5e00014-0000-0000-0000-000000000015'
\set questionID 'a5e00014-0000-0000-0000-00000000000f'
\set questionsDraftSurveyID 'a5e00014-0000-0000-0000-00000000001b'
\set readyDateSurveyID 'a5e00014-0000-0000-0000-000000000010'
\set readyQuestionsSurveyID 'a5e00014-0000-0000-0000-000000000011'
\set scheduledAnonymousSurveyID 'a5e00014-0000-0000-0000-000000000016'
\set staleSurveyID 'a5e00014-0000-0000-0000-000000000012'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community hosting the surveyed events
select fx_community(:'communityID');

-- Organizer updating the surveys
select fx_user(:'actorUserID');

-- Event category used by the surveyed events
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category used by the group
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group hosting the surveyed events
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Canceled event whose surveys cannot be managed
select fx_event(:'canceledEventID', :'groupID', :'eventCategoryID', jsonb_build_object('canceled', true));

-- Published event that already ended
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', '2025-01-01 12:00:00+00',
    'published', true,
    'starts_at', '2025-01-01 10:00:00+00'
));

-- Event of the same group that does not own the updated surveys
select fx_event(:'otherEventID', :'groupID', :'eventCategoryID');

-- Draft anonymous survey that becomes identified
insert into event_survey (event_survey_id, event_id, title)
values (:'anonymityDraftSurveyID', :'eventID', 'Anonymity draft survey');

-- Ready survey with responses whose title, introduction and dates change
insert into event_survey (
    event_survey_id,
    event_id,
    questions,
    status,
    title,

    closes_at,
    first_response_at
) values (
    :'answeredDatesSurveyID',
    :'eventID',
    jsonb_build_array(jsonb_build_object(
        'id', :'questionID'::uuid,
        'kind', 'free-text',
        'prompt', 'Feedback',
        'required', false
    )),
    'ready',
    'Answered dates survey',

    '2099-01-01 00:00:00+00',
    '2025-01-02 10:00:00+00'
);

-- Ready survey that already has responses
insert into event_survey (
    event_survey_id,
    event_id,
    questions,
    status,
    title,

    closes_at,
    first_response_at
) values (
    :'answeredSurveyID',
    :'eventID',
    jsonb_build_array(jsonb_build_object(
        'id', :'questionID'::uuid,
        'kind', 'free-text',
        'prompt', 'Feedback',
        'required', false
    )),
    'ready',
    'Answered survey',

    '2099-01-01 00:00:00+00',
    '2025-01-02 10:00:00+00'
);

-- Survey of the canceled event
insert into event_survey (event_survey_id, event_id, title)
values (:'canceledEventSurveyID', :'canceledEventID', 'Canceled event survey');

-- Ready answered survey closed by a past closing date
insert into event_survey (
    event_survey_id,
    event_id,
    questions,
    status,
    title,

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
    'ready',
    'Closed answered survey',

    '2025-01-05 00:00:00+00',
    '2025-01-02 10:00:00+00'
);

-- Draft survey whose audience changes
insert into event_survey (event_survey_id, event_id, title)
values (:'configSurveyID', :'eventID', 'Config survey');

-- Draft survey whose closing date moves to the past
insert into event_survey (event_survey_id, event_id, title)
values (:'draftDatesSurveyID', :'eventID', 'Draft dates survey');

-- Draft survey with a sub-second opening time and a later revision
insert into event_survey (
    event_survey_id,
    event_id,
    revision,
    title,

    opens_at
) values (
    :'draftSurveyID',
    :'eventID',
    3,
    'Draft survey',

    '2025-03-01 10:00:00.400+00'
);

-- Draft survey with sub-second dates edited with whole-second dates
insert into event_survey (
    event_survey_id,
    event_id,
    title,

    closes_at,
    opens_at
) values (
    :'fractionalDatesSurveyID',
    :'eventID',
    'Fractional dates survey',

    '2099-01-01 00:00:00.250+00',
    '2098-12-01 00:00:00.400+00'
);

-- Open anonymous survey whose opening email was not processed yet
insert into event_survey (event_survey_id, event_id, questions, status, title)
values (
    :'openAnonymousSurveyID',
    :'eventID',
    jsonb_build_array(jsonb_build_object(
        'id', :'questionID'::uuid,
        'kind', 'free-text',
        'prompt', 'Feedback',
        'required', false
    )),
    'ready',
    'Open anonymous survey'
);

-- Open identified survey whose opening email was processed
insert into event_survey (
    event_survey_id,
    anonymous,
    event_id,
    questions,
    status,
    title,

    open_notification_processed_at,
    open_notification_recipients
) values (
    :'openIdentifiedSurveyID',
    false,
    :'eventID',
    jsonb_build_array(jsonb_build_object(
        'id', :'questionID'::uuid,
        'kind', 'free-text',
        'prompt', 'Feedback',
        'required', false
    )),
    'ready',
    'Open identified survey',

    '2025-01-01 12:05:00+00',
    0
);

-- Survey of another event of the group
insert into event_survey (event_survey_id, event_id, title)
values (:'otherEventSurveyID', :'otherEventID', 'Other event survey');

-- Scheduled anonymous survey whose opening email was already processed
insert into event_survey (
    event_survey_id,
    event_id,
    questions,
    status,
    title,

    open_notification_processed_at,
    open_notification_recipients,
    opens_at
) values (
    :'processedAnonymousSurveyID',
    :'eventID',
    jsonb_build_array(jsonb_build_object(
        'id', :'questionID'::uuid,
        'kind', 'free-text',
        'prompt', 'Feedback',
        'required', false
    )),
    'ready',
    'Processed anonymous survey',

    '2025-01-01 12:05:00+00',
    0,
    '2099-01-01 00:00:00+00'
);

-- Draft survey whose questions change
insert into event_survey (event_survey_id, event_id, title)
values (:'questionsDraftSurveyID', :'eventID', 'Questions draft survey');

-- Ready survey whose closing date changes
insert into event_survey (
    event_survey_id,
    event_id,
    questions,
    status,
    title,

    closes_at
) values (
    :'readyDateSurveyID',
    :'eventID',
    jsonb_build_array(jsonb_build_object(
        'id', :'questionID'::uuid,
        'kind', 'free-text',
        'prompt', 'Feedback',
        'required', false
    )),
    'ready',
    'Ready date survey',

    '2099-01-01 00:00:00+00'
);

-- Ready survey whose questions change
insert into event_survey (event_survey_id, event_id, questions, status, title)
values (
    :'readyQuestionsSurveyID',
    :'eventID',
    jsonb_build_array(jsonb_build_object(
        'id', :'questionID'::uuid,
        'kind', 'free-text',
        'prompt', 'Feedback',
        'required', false
    )),
    'ready',
    'Ready questions survey'
);

-- Scheduled anonymous survey whose opening email was not processed yet
insert into event_survey (
    event_survey_id,
    event_id,
    questions,
    status,
    title,

    opens_at
) values (
    :'scheduledAnonymousSurveyID',
    :'eventID',
    jsonb_build_array(jsonb_build_object(
        'id', :'questionID'::uuid,
        'kind', 'free-text',
        'prompt', 'Feedback',
        'required', false
    )),
    'ready',
    'Scheduled anonymous survey',

    '2099-01-01 00:00:00+00'
);

-- Draft survey edited from a stale form
insert into event_survey (event_survey_id, event_id, revision, title)
values (:'staleSurveyID', :'eventID', 2, 'Stale survey');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should bump the revision when the anonymity changes
select lives_ok(
    format(
        $$select update_event_survey(%L::uuid, %L::uuid, %L::uuid, %L::uuid, 1, '{"anonymous": false, "audience": "confirmed", "questions": [], "title": "Anonymity draft survey"}'::jsonb)$$,
        :'actorUserID', :'groupID', :'eventID', :'anonymityDraftSurveyID'
    ),
    'Should bump the revision when the anonymity changes'
);
select results_eq(
    format(
        $$
            select s.anonymous, s.revision
            from event_survey s
            where s.event_survey_id = %L
        $$,
        :'anonymityDraftSurveyID'
    ),
    $$ values (false, 2::bigint) $$,
    'Should store the anonymity change with a bumped revision'
);

-- Should bump the revision when the audience changes
select lives_ok(
    format(
        $$select update_event_survey(%L::uuid, %L::uuid, %L::uuid, %L::uuid, 1, '{"anonymous": true, "audience": "checked-in", "questions": [], "title": "Config survey"}'::jsonb)$$,
        :'actorUserID', :'groupID', :'eventID', :'configSurveyID'
    ),
    'Should bump the revision when the audience changes'
);
select results_eq(
    format(
        $$
            select s.audience, s.revision, s.updated_at is not null
            from event_survey s
            where s.event_survey_id = %L
        $$,
        :'configSurveyID'
    ),
    $$ values ('checked-in', 2::bigint, true) $$,
    'Should store the audience change with a bumped revision'
);

-- Should bump the revision when the questions change
select lives_ok(
    format(
        $$select update_event_survey(%L::uuid, %L::uuid, %L::uuid, %L::uuid, 1, jsonb_build_object('anonymous', true, 'audience', 'confirmed', 'questions', jsonb_build_array(jsonb_build_object('id', %L::uuid, 'kind', 'free-text', 'prompt', 'Feedback', 'required', false)), 'title', 'Questions draft survey'))$$,
        :'actorUserID', :'groupID', :'eventID', :'questionsDraftSurveyID', :'questionID'
    ),
    'Should bump the revision when the questions change'
);
select results_eq(
    format(
        $$
            select jsonb_array_length(s.questions), s.revision
            from event_survey s
            where s.event_survey_id = %L
        $$,
        :'questionsDraftSurveyID'
    ),
    $$ values (1, 2::bigint) $$,
    'Should store the questions change with a bumped revision'
);

-- Should keep stored dates and the revision when dates match at whole seconds
select lives_ok(
    format(
        $$select update_event_survey(%L::uuid, %L::uuid, %L::uuid, %L::uuid, 1, '{"anonymous": true, "audience": "confirmed", "closes_at": "2099-01-01T00:00:00", "opens_at": "2098-12-01T00:00:00", "questions": [], "title": "Renamed fractional survey"}'::jsonb)$$,
        :'actorUserID', :'groupID', :'eventID', :'fractionalDatesSurveyID'
    ),
    'Should keep stored dates and the revision when dates match at whole seconds'
);
select results_eq(
    format(
        $$
            select s.closes_at, s.opens_at, s.revision, s.title
            from event_survey s
            where s.event_survey_id = %L
        $$,
        :'fractionalDatesSurveyID'
    ),
    $$
        values (
            '2099-01-01 00:00:00.250+00'::timestamptz,
            '2098-12-01 00:00:00.400+00'::timestamptz,
            1::bigint,
            'Renamed fractional survey'
        )
    $$,
    'Should store the title without rewriting dates that match at whole seconds'
);

-- Should keep the revision when only the title and description change
select lives_ok(
    format(
        $$select update_event_survey(%L::uuid, %L::uuid, %L::uuid, %L::uuid, 3, '{"anonymous": true, "audience": "confirmed", "description": "New intro", "opens_at": "2025-03-01T10:00:00", "questions": [], "title": "Renamed draft"}'::jsonb)$$,
        :'actorUserID', :'groupID', :'eventID', :'draftSurveyID'
    ),
    'Should keep the revision when only the title and description change'
);
select results_eq(
    format(
        $$
            select s.description, s.revision, s.title, s.updated_at is not null
            from event_survey s
            where s.event_survey_id = %L
        $$,
        :'draftSurveyID'
    ),
    $$ values ('New intro', 3::bigint, 'Renamed draft', true) $$,
    'Should store title and description edits without a bumped revision'
);

-- Should let anonymous surveys become identified while scheduled before their opening email
select lives_ok(
    format(
        $$select update_event_survey(%L::uuid, %L::uuid, %L::uuid, %L::uuid, 1, jsonb_build_object('anonymous', false, 'audience', 'confirmed', 'opens_at', '2099-01-01T00:00:00', 'questions', jsonb_build_array(jsonb_build_object('id', %L::uuid, 'kind', 'free-text', 'prompt', 'Feedback', 'required', false)), 'title', 'Scheduled anonymous survey'))$$,
        :'actorUserID', :'groupID', :'eventID', :'scheduledAnonymousSurveyID', :'questionID'
    ),
    'Should let anonymous surveys become identified while scheduled before their opening email'
);
select results_eq(
    format(
        $$
            select s.anonymous, s.revision
            from event_survey s
            where s.event_survey_id = %L
        $$,
        :'scheduledAnonymousSurveyID'
    ),
    $$ values (false, 2::bigint) $$,
    'Should store the identified setting of scheduled surveys with a bumped revision'
);

-- Should let answered surveys closed by date change their title
select lives_ok(
    format(
        $$select update_event_survey(%L::uuid, %L::uuid, %L::uuid, %L::uuid, 1, jsonb_build_object('anonymous', true, 'audience', 'confirmed', 'closes_at', '2025-01-05T00:00:00', 'questions', jsonb_build_array(jsonb_build_object('id', %L::uuid, 'kind', 'free-text', 'prompt', 'Feedback', 'required', false)), 'title', 'Renamed closed survey'))$$,
        :'actorUserID', :'groupID', :'eventID', :'closedAnsweredSurveyID', :'questionID'
    ),
    'Should let answered surveys closed by date change their title'
);
select results_eq(
    format(
        $$
            select s.revision, s.title
            from event_survey s
            where s.event_survey_id = %L
        $$,
        :'closedAnsweredSurveyID'
    ),
    $$ values (1::bigint, 'Renamed closed survey') $$,
    'Should store the title of answered surveys closed by date'
);

-- Should let identified surveys become anonymous after they open
select lives_ok(
    format(
        $$select update_event_survey(%L::uuid, %L::uuid, %L::uuid, %L::uuid, 1, jsonb_build_object('anonymous', true, 'audience', 'confirmed', 'questions', jsonb_build_array(jsonb_build_object('id', %L::uuid, 'kind', 'free-text', 'prompt', 'Feedback', 'required', false)), 'title', 'Open identified survey'))$$,
        :'actorUserID', :'groupID', :'eventID', :'openIdentifiedSurveyID', :'questionID'
    ),
    'Should let identified surveys become anonymous after they open'
);
select results_eq(
    format(
        $$
            select s.anonymous, s.revision
            from event_survey s
            where s.event_survey_id = %L
        $$,
        :'openIdentifiedSurveyID'
    ),
    $$ values (true, 2::bigint) $$,
    'Should store the anonymous setting of open surveys with a bumped revision'
);

-- Should reject anonymity changes once the survey has responses
select throws_ok(
    format(
        $$select update_event_survey(%L::uuid, %L::uuid, %L::uuid, %L::uuid, 1, jsonb_build_object('anonymous', false, 'audience', 'confirmed', 'closes_at', '2099-01-01T00:00:00', 'questions', jsonb_build_array(jsonb_build_object('id', %L::uuid, 'kind', 'free-text', 'prompt', 'Feedback', 'required', false)), 'title', 'Answered survey'))$$,
        :'actorUserID', :'groupID', :'eventID', :'answeredSurveyID', :'questionID'
    ),
    'OCG01',
    'survey questions, audience and anonymity cannot change once it has responses',
    'Should reject anonymity changes once the survey has responses'
);

-- Should reject audience changes once the survey has responses
select throws_ok(
    format(
        $$select update_event_survey(%L::uuid, %L::uuid, %L::uuid, %L::uuid, 1, jsonb_build_object('anonymous', true, 'audience', 'checked-in', 'closes_at', '2099-01-01T00:00:00', 'questions', jsonb_build_array(jsonb_build_object('id', %L::uuid, 'kind', 'free-text', 'prompt', 'Feedback', 'required', false)), 'title', 'Answered survey'))$$,
        :'actorUserID', :'groupID', :'eventID', :'answeredSurveyID', :'questionID'
    ),
    'OCG01',
    'survey questions, audience and anonymity cannot change once it has responses',
    'Should reject audience changes once the survey has responses'
);

-- Should reject canceled events
select throws_ok(
    format(
        $$select update_event_survey(%L::uuid, %L::uuid, %L::uuid, %L::uuid, 1, '{"anonymous": true, "audience": "confirmed", "questions": [], "title": "Survey"}'::jsonb)$$,
        :'actorUserID', :'groupID', :'canceledEventID', :'canceledEventSurveyID'
    ),
    'OCG01',
    'event not found or inactive',
    'Should reject canceled events'
);

-- Should reject invalid payloads
select throws_ok(
    format(
        $$select update_event_survey(%L::uuid, %L::uuid, %L::uuid, %L::uuid, 2, '{"anonymous": true, "audience": "everyone", "questions": [], "title": "Survey"}'::jsonb)$$,
        :'actorUserID', :'groupID', :'eventID', :'staleSurveyID'
    ),
    'OCG01',
    'event survey audience is invalid',
    'Should reject invalid payloads'
);

-- Should reject question changes once the survey has responses
select throws_ok(
    format(
        $$select update_event_survey(%L::uuid, %L::uuid, %L::uuid, %L::uuid, 1, jsonb_build_object('anonymous', true, 'audience', 'confirmed', 'closes_at', '2099-01-01T00:00:00', 'questions', jsonb_build_array(jsonb_build_object('id', %L::uuid, 'kind', 'free-text', 'prompt', 'Renamed feedback', 'required', false)), 'title', 'Answered survey'))$$,
        :'actorUserID', :'groupID', :'eventID', :'answeredSurveyID', :'questionID'
    ),
    'OCG01',
    'survey questions, audience and anonymity cannot change once it has responses',
    'Should reject question changes once the survey has responses'
);

-- Should reject stale revisions
select throws_ok(
    format(
        $$select update_event_survey(%L::uuid, %L::uuid, %L::uuid, %L::uuid, 1, '{"anonymous": true, "audience": "confirmed", "questions": [], "title": "Survey"}'::jsonb)$$,
        :'actorUserID', :'groupID', :'eventID', :'staleSurveyID'
    ),
    'OCG01',
    'the survey changed; review and try again',
    'Should reject stale revisions'
);

-- Should reject surveys of another event
select throws_ok(
    format(
        $$select update_event_survey(%L::uuid, %L::uuid, %L::uuid, %L::uuid, 1, '{"anonymous": true, "audience": "confirmed", "questions": [], "title": "Survey"}'::jsonb)$$,
        :'actorUserID', :'groupID', :'eventID', :'otherEventSurveyID'
    ),
    'OCG01',
    'event survey not found',
    'Should reject surveys of another event'
);

-- Should reject turning off anonymity after the opening email is processed
select throws_ok(
    format(
        $$select update_event_survey(%L::uuid, %L::uuid, %L::uuid, %L::uuid, 1, jsonb_build_object('anonymous', false, 'audience', 'confirmed', 'opens_at', '2099-01-01T00:00:00', 'questions', jsonb_build_array(jsonb_build_object('id', %L::uuid, 'kind', 'free-text', 'prompt', 'Feedback', 'required', false)), 'title', 'Processed anonymous survey'))$$,
        :'actorUserID', :'groupID', :'eventID', :'processedAnonymousSurveyID', :'questionID'
    ),
    'OCG01',
    'anonymity cannot be turned off after the survey has opened',
    'Should reject turning off anonymity after the opening email is processed'
);

-- Should reject turning off anonymity once the survey is open
select throws_ok(
    format(
        $$select update_event_survey(%L::uuid, %L::uuid, %L::uuid, %L::uuid, 1, jsonb_build_object('anonymous', false, 'audience', 'confirmed', 'questions', jsonb_build_array(jsonb_build_object('id', %L::uuid, 'kind', 'free-text', 'prompt', 'Feedback', 'required', false)), 'title', 'Open anonymous survey'))$$,
        :'actorUserID', :'groupID', :'eventID', :'openAnonymousSurveyID', :'questionID'
    ),
    'OCG01',
    'anonymity cannot be turned off after the survey has opened',
    'Should reject turning off anonymity once the survey is open'
);

-- Should revalidate the schedule of ready surveys when a date changes
select throws_ok(
    format(
        $$select update_event_survey(%L::uuid, %L::uuid, %L::uuid, %L::uuid, 1, jsonb_build_object('anonymous', true, 'audience', 'confirmed', 'closes_at', '2025-01-10T10:00:00', 'questions', jsonb_build_array(jsonb_build_object('id', %L::uuid, 'kind', 'free-text', 'prompt', 'Feedback', 'required', false)), 'title', 'Ready date survey'))$$,
        :'actorUserID', :'groupID', :'eventID', :'readyDateSurveyID', :'questionID'
    ),
    'OCG01',
    'event survey closing date must be in the future',
    'Should revalidate the schedule of ready surveys when a date changes'
);

-- Should revalidate the schedule of ready surveys when the questions change
select throws_ok(
    format(
        $$select update_event_survey(%L::uuid, %L::uuid, %L::uuid, %L::uuid, 1, '{"anonymous": true, "audience": "confirmed", "questions": [], "title": "Ready questions survey"}'::jsonb)$$,
        :'actorUserID', :'groupID', :'eventID', :'readyQuestionsSurveyID'
    ),
    'OCG01',
    'event survey must have at least one question',
    'Should revalidate the schedule of ready surveys when the questions change'
);

-- Should update draft dates without schedule validation
select lives_ok(
    format(
        $$select update_event_survey(%L::uuid, %L::uuid, %L::uuid, %L::uuid, 1, '{"anonymous": true, "audience": "confirmed", "closes_at": "2025-01-10T10:00:00", "questions": [], "title": "Draft dates survey"}'::jsonb)$$,
        :'actorUserID', :'groupID', :'eventID', :'draftDatesSurveyID'
    ),
    'Should update draft dates without schedule validation'
);
select results_eq(
    format(
        $$
            select s.closes_at, s.revision, s.status
            from event_survey s
            where s.event_survey_id = %L
        $$,
        :'draftDatesSurveyID'
    ),
    $$ values ('2025-01-10 10:00:00+00'::timestamptz, 2::bigint, 'draft') $$,
    'Should store the past closing date of drafts with a bumped revision'
);

-- Should update the title, introduction and dates of surveys with responses
select lives_ok(
    format(
        $$select update_event_survey(%L::uuid, %L::uuid, %L::uuid, %L::uuid, 1, jsonb_build_object('anonymous', true, 'audience', 'confirmed', 'closes_at', '2099-02-01T00:00:00', 'description', 'New intro', 'questions', jsonb_build_array(jsonb_build_object('id', %L::uuid, 'kind', 'free-text', 'prompt', 'Feedback', 'required', false)), 'title', 'Renamed answered survey'))$$,
        :'actorUserID', :'groupID', :'eventID', :'answeredDatesSurveyID', :'questionID'
    ),
    'Should update the title, introduction and dates of surveys with responses'
);
select results_eq(
    format(
        $$
            select s.closes_at, s.description, s.revision, s.title
            from event_survey s
            where s.event_survey_id = %L
        $$,
        :'answeredDatesSurveyID'
    ),
    $$
        values (
            '2099-02-01 00:00:00+00'::timestamptz,
            'New intro',
            2::bigint,
            'Renamed answered survey'
        )
    $$,
    'Should store the title, introduction and dates of surveys with responses'
);

-- Should record an audit row per successful update
select results_eq(
    format(
        $$
            select
                al.action,
                al.actor_user_id,
                al.community_id,
                al.details->>'title',
                al.event_id,
                al.group_id,
                al.resource_id,
                al.resource_type
            from audit_log al
            where al.group_id = %L
            order by al.resource_id
        $$,
        :'groupID'
    ),
    format(
        $$
            values
                ('event_survey_updated', %L::uuid, %L::uuid, 'Renamed closed survey', %L::uuid, %L::uuid, %L::uuid, 'event_survey'),
                ('event_survey_updated', %L::uuid, %L::uuid, 'Config survey', %L::uuid, %L::uuid, %L::uuid, 'event_survey'),
                ('event_survey_updated', %L::uuid, %L::uuid, 'Renamed draft', %L::uuid, %L::uuid, %L::uuid, 'event_survey'),
                ('event_survey_updated', %L::uuid, %L::uuid, 'Open identified survey', %L::uuid, %L::uuid, %L::uuid, 'event_survey'),
                ('event_survey_updated', %L::uuid, %L::uuid, 'Scheduled anonymous survey', %L::uuid, %L::uuid, %L::uuid, 'event_survey'),
                ('event_survey_updated', %L::uuid, %L::uuid, 'Anonymity draft survey', %L::uuid, %L::uuid, %L::uuid, 'event_survey'),
                ('event_survey_updated', %L::uuid, %L::uuid, 'Renamed answered survey', %L::uuid, %L::uuid, %L::uuid, 'event_survey'),
                ('event_survey_updated', %L::uuid, %L::uuid, 'Draft dates survey', %L::uuid, %L::uuid, %L::uuid, 'event_survey'),
                ('event_survey_updated', %L::uuid, %L::uuid, 'Renamed fractional survey', %L::uuid, %L::uuid, %L::uuid, 'event_survey'),
                ('event_survey_updated', %L::uuid, %L::uuid, 'Questions draft survey', %L::uuid, %L::uuid, %L::uuid, 'event_survey')
        $$,
        :'actorUserID', :'communityID', :'eventID', :'groupID', :'closedAnsweredSurveyID',
        :'actorUserID', :'communityID', :'eventID', :'groupID', :'configSurveyID',
        :'actorUserID', :'communityID', :'eventID', :'groupID', :'draftSurveyID',
        :'actorUserID', :'communityID', :'eventID', :'groupID', :'openIdentifiedSurveyID',
        :'actorUserID', :'communityID', :'eventID', :'groupID', :'scheduledAnonymousSurveyID',
        :'actorUserID', :'communityID', :'eventID', :'groupID', :'anonymityDraftSurveyID',
        :'actorUserID', :'communityID', :'eventID', :'groupID', :'answeredDatesSurveyID',
        :'actorUserID', :'communityID', :'eventID', :'groupID', :'draftDatesSurveyID',
        :'actorUserID', :'communityID', :'eventID', :'groupID', :'fractionalDatesSurveyID',
        :'actorUserID', :'communityID', :'eventID', :'groupID', :'questionsDraftSurveyID'
    ),
    'Should record an audit row per successful update'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
