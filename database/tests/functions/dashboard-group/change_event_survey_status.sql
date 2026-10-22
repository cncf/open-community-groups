-- Tests changing the status of surveys of group events.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(40);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorUserID 'a5e00016-0000-0000-0000-000000000001'
\set answeredScheduledSurveyID 'a5e00016-0000-0000-0000-000000000002'
\set canceledEventID 'a5e00016-0000-0000-0000-000000000003'
\set canceledEventSurveyID 'a5e00016-0000-0000-0000-000000000004'
\set closedSurveyID 'a5e00016-0000-0000-0000-000000000005'
\set closedUndatedSurveyID 'a5e00016-0000-0000-0000-00000000001b'
\set communityID 'a5e00016-0000-0000-0000-000000000006'
\set datedMismatchSurveyID 'a5e00016-0000-0000-0000-000000000007'
\set emptyDraftSurveyID 'a5e00016-0000-0000-0000-000000000008'
\set eventCategoryID 'a5e00016-0000-0000-0000-000000000009'
\set expiredSurveyID 'a5e00016-0000-0000-0000-00000000000a'
\set futureEventID 'a5e00016-0000-0000-0000-00000000000b'
\set groupCategoryID 'a5e00016-0000-0000-0000-00000000000c'
\set groupID 'a5e00016-0000-0000-0000-00000000000d'
\set lifecycleEventID 'a5e00016-0000-0000-0000-00000000001c'
\set lifecycleGroupID 'a5e00016-0000-0000-0000-00000000001d'
\set lifecycleSurveyID 'a5e00016-0000-0000-0000-00000000001e'
\set markReadyFutureSurveyID 'a5e00016-0000-0000-0000-00000000000e'
\set markReadyPastSurveyID 'a5e00016-0000-0000-0000-00000000000f'
\set markReadyUndatedSurveyID 'a5e00016-0000-0000-0000-000000000010'
\set openCloseSurveyID 'a5e00016-0000-0000-0000-000000000011'
\set openRejectSurveyID 'a5e00016-0000-0000-0000-000000000012'
\set otherEventSurveyID 'a5e00016-0000-0000-0000-000000000013'
\set pastConfirmationSurveyID 'a5e00016-0000-0000-0000-00000000001f'
\set pastEventID 'a5e00016-0000-0000-0000-000000000014'
\set processedScheduledSurveyID 'a5e00016-0000-0000-0000-000000000015'
\set questionID 'a5e00016-0000-0000-0000-000000000016'
\set rescheduledSurveyID 'a5e00016-0000-0000-0000-000000000017'
\set scheduledSurveyID 'a5e00016-0000-0000-0000-000000000018'
\set undatedEventID 'a5e00016-0000-0000-0000-000000000019'
\set undatedMismatchSurveyID 'a5e00016-0000-0000-0000-00000000001a'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community hosting the surveyed events
select fx_community(:'communityID');

-- Organizer changing the survey statuses
select fx_user(:'actorUserID');

-- Event category used by the surveyed events
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category used by the group
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group hosting the surveyed events
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Group hosting the event whose survey walks through every transition
select fx_group(:'lifecycleGroupID', :'communityID', :'groupCategoryID');

-- Canceled event whose surveys cannot be managed
select fx_event(:'canceledEventID', :'groupID', :'eventCategoryID', jsonb_build_object('canceled', true));

-- Published event ending in the future
select fx_event(:'futureEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', '2099-01-01 12:00:00+00',
    'published', true,
    'starts_at', '2099-01-01 10:00:00+00'
));

-- Published event that already ended
select fx_event(:'pastEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', '2025-01-01 12:00:00+00',
    'published', true,
    'starts_at', '2025-01-01 10:00:00+00'
));

-- Published event that already ended, hosting the lifecycle survey
select fx_event(:'lifecycleEventID', :'lifecycleGroupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', '2025-01-01 12:00:00+00',
    'published', true,
    'starts_at', '2025-01-01 10:00:00+00'
));

-- Published event without dates
select fx_event(:'undatedEventID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));

-- Scheduled survey that already has responses
insert into event_survey (
    event_survey_id,
    event_id,
    questions,
    status,
    title,

    first_response_at
) values (
    :'answeredScheduledSurveyID',
    :'futureEventID',
    jsonb_build_array(jsonb_build_object(
        'id', :'questionID'::uuid,
        'kind', 'free-text',
        'prompt', 'Feedback',
        'required', false
    )),
    'ready',
    'Answered scheduled survey',

    '2025-01-02 10:00:00+00'
);

-- Survey of the canceled event
insert into event_survey (
    event_survey_id,
    event_id,
    status,
    title
) values (
    :'canceledEventSurveyID',
    :'canceledEventID',
    'draft',
    'Canceled event survey'
);

-- Survey closed manually before its closing date
insert into event_survey (
    event_survey_id,
    event_id,
    questions,
    status,
    title,

    closed_at,
    closes_at
) values (
    :'closedSurveyID',
    :'pastEventID',
    jsonb_build_array(jsonb_build_object(
        'id', :'questionID'::uuid,
        'kind', 'free-text',
        'prompt', 'Feedback',
        'required', false
    )),
    'ready',
    'Closed survey',

    '2025-01-03 10:00:00+00',
    '2099-01-01 00:00:00+00'
);

-- Survey closed manually without a closing date
insert into event_survey (
    event_survey_id,
    event_id,
    questions,
    status,
    title,

    closed_at
) values (
    :'closedUndatedSurveyID',
    :'pastEventID',
    jsonb_build_array(jsonb_build_object(
        'id', :'questionID'::uuid,
        'kind', 'free-text',
        'prompt', 'Feedback',
        'required', false
    )),
    'ready',
    'Closed survey without closing date',

    '2025-01-03 10:00:00+00'
);

-- Draft survey confirmed before its event got dates
insert into event_survey (
    event_survey_id,
    event_id,
    questions,
    status,
    title
) values (
    :'datedMismatchSurveyID',
    :'futureEventID',
    jsonb_build_array(jsonb_build_object(
        'id', :'questionID'::uuid,
        'kind', 'free-text',
        'prompt', 'Feedback',
        'required', false
    )),
    'draft',
    'Dated mismatch survey'
);

-- Draft survey without questions
insert into event_survey (
    event_survey_id,
    event_id,
    status,
    title
) values (
    :'emptyDraftSurveyID',
    :'pastEventID',
    'draft',
    'Empty draft survey'
);

-- Survey closed by a past closing date
insert into event_survey (
    event_survey_id,
    event_id,
    questions,
    status,
    title,

    closes_at
) values (
    :'expiredSurveyID',
    :'pastEventID',
    jsonb_build_array(jsonb_build_object(
        'id', :'questionID'::uuid,
        'kind', 'free-text',
        'prompt', 'Feedback',
        'required', false
    )),
    'ready',
    'Expired survey',

    '2025-01-05 00:00:00+00'
);

-- Draft survey walked through every transition
insert into event_survey (
    event_survey_id,
    event_id,
    questions,
    status,
    title
) values (
    :'lifecycleSurveyID',
    :'lifecycleEventID',
    jsonb_build_array(jsonb_build_object(
        'id', :'questionID'::uuid,
        'kind', 'free-text',
        'prompt', 'Feedback',
        'required', false
    )),
    'draft',
    'Lifecycle survey'
);

-- Draft survey of the future event marked ready
insert into event_survey (
    event_survey_id,
    event_id,
    questions,
    status,
    title
) values (
    :'markReadyFutureSurveyID',
    :'futureEventID',
    jsonb_build_array(jsonb_build_object(
        'id', :'questionID'::uuid,
        'kind', 'free-text',
        'prompt', 'Feedback',
        'required', false
    )),
    'draft',
    'Future draft survey'
);

-- Draft survey of the past event marked ready
insert into event_survey (
    event_survey_id,
    event_id,
    questions,
    status,
    title
) values (
    :'markReadyPastSurveyID',
    :'pastEventID',
    jsonb_build_array(jsonb_build_object(
        'id', :'questionID'::uuid,
        'kind', 'free-text',
        'prompt', 'Feedback',
        'required', false
    )),
    'draft',
    'Past draft survey'
);

-- Draft survey of the undated event marked ready
insert into event_survey (
    event_survey_id,
    event_id,
    questions,
    status,
    title
) values (
    :'markReadyUndatedSurveyID',
    :'undatedEventID',
    jsonb_build_array(jsonb_build_object(
        'id', :'questionID'::uuid,
        'kind', 'free-text',
        'prompt', 'Feedback',
        'required', false
    )),
    'draft',
    'Undated draft survey'
);

-- Open survey closed by the organizer
insert into event_survey (
    event_survey_id,
    event_id,
    questions,
    status,
    title
) values (
    :'openCloseSurveyID',
    :'pastEventID',
    jsonb_build_array(jsonb_build_object(
        'id', :'questionID'::uuid,
        'kind', 'free-text',
        'prompt', 'Feedback',
        'required', false
    )),
    'ready',
    'Open survey to close'
);

-- Open survey used by rejected transitions
insert into event_survey (
    event_survey_id,
    event_id,
    questions,
    status,
    title
) values (
    :'openRejectSurveyID',
    :'pastEventID',
    jsonb_build_array(jsonb_build_object(
        'id', :'questionID'::uuid,
        'kind', 'free-text',
        'prompt', 'Feedback',
        'required', false
    )),
    'ready',
    'Open survey'
);

-- Survey of another event of the group
insert into event_survey (
    event_survey_id,
    event_id,
    status,
    title
) values (
    :'otherEventSurveyID',
    :'futureEventID',
    'draft',
    'Other event survey'
);

-- Draft survey of the future event confirmed with a past opening
insert into event_survey (
    event_survey_id,
    event_id,
    questions,
    status,
    title
) values (
    :'pastConfirmationSurveyID',
    :'futureEventID',
    jsonb_build_array(jsonb_build_object(
        'id', :'questionID'::uuid,
        'kind', 'free-text',
        'prompt', 'Feedback',
        'required', false
    )),
    'draft',
    'Past confirmation survey'
);

-- Scheduled survey whose opening email was processed
insert into event_survey (
    event_survey_id,
    event_id,
    questions,
    status,
    title,

    open_notification_processed_at,
    open_notification_recipients
) values (
    :'processedScheduledSurveyID',
    :'futureEventID',
    jsonb_build_array(jsonb_build_object(
        'id', :'questionID'::uuid,
        'kind', 'free-text',
        'prompt', 'Feedback',
        'required', false
    )),
    'ready',
    'Processed scheduled survey',

    '2025-01-02 10:00:00+00',
    0
);

-- Draft survey confirmed before its event was rescheduled
insert into event_survey (
    event_survey_id,
    event_id,
    questions,
    status,
    title
) values (
    :'rescheduledSurveyID',
    :'futureEventID',
    jsonb_build_array(jsonb_build_object(
        'id', :'questionID'::uuid,
        'kind', 'free-text',
        'prompt', 'Feedback',
        'required', false
    )),
    'draft',
    'Rescheduled draft survey'
);

-- Scheduled survey moved back to draft
insert into event_survey (
    event_survey_id,
    event_id,
    questions,
    status,
    title
) values (
    :'scheduledSurveyID',
    :'futureEventID',
    jsonb_build_array(jsonb_build_object(
        'id', :'questionID'::uuid,
        'kind', 'free-text',
        'prompt', 'Feedback',
        'required', false
    )),
    'ready',
    'Scheduled survey'
);

-- Draft survey confirmed before its event lost its dates
insert into event_survey (
    event_survey_id,
    event_id,
    questions,
    status,
    title
) values (
    :'undatedMismatchSurveyID',
    :'undatedEventID',
    jsonb_build_array(jsonb_build_object(
        'id', :'questionID'::uuid,
        'kind', 'free-text',
        'prompt', 'Feedback',
        'required', false
    )),
    'draft',
    'Undated mismatch survey'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should close open surveys
select lives_ok(
    format(
        $$select change_event_survey_status(%L::uuid, %L::uuid, %L::uuid, %L::uuid, 1, null::timestamptz, 'close')$$,
        :'actorUserID', :'groupID', :'pastEventID', :'openCloseSurveyID'
    ),
    'Should close open surveys'
);
select results_eq(
    format(
        $$
            select s.closed_at is not null, s.revision, s.status, s.updated_at is not null
            from event_survey s
            where s.event_survey_id = %L
        $$,
        :'openCloseSurveyID'
    ),
    $$ values (true, 2::bigint, 'ready', true) $$,
    'Should store the manual close with a bumped revision'
);

-- Should mark drafts ready when both opening times are in the past
select lives_ok(
    format(
        $$select change_event_survey_status(%L::uuid, %L::uuid, %L::uuid, %L::uuid, 1, '2025-01-02 00:00:00+00'::timestamptz, 'mark-ready')$$,
        :'actorUserID', :'groupID', :'pastEventID', :'markReadyPastSurveyID'
    ),
    'Should mark drafts ready when both opening times are in the past'
);
select results_eq(
    format(
        $$
            select s.closed_at is not null, s.revision, s.status, s.updated_at is not null
            from event_survey s
            where s.event_survey_id = %L
        $$,
        :'markReadyPastSurveyID'
    ),
    $$ values (false, 2::bigint, 'ready', true) $$,
    'Should store past drafts as ready with a bumped revision'
);

-- Should mark drafts ready when both opening times are unknown
select lives_ok(
    format(
        $$select change_event_survey_status(%L::uuid, %L::uuid, %L::uuid, %L::uuid, 1, null::timestamptz, 'mark-ready')$$,
        :'actorUserID', :'groupID', :'undatedEventID', :'markReadyUndatedSurveyID'
    ),
    'Should mark drafts ready when both opening times are unknown'
);
select results_eq(
    format(
        $$
            select s.closed_at is not null, s.revision, s.status, s.updated_at is not null
            from event_survey s
            where s.event_survey_id = %L
        $$,
        :'markReadyUndatedSurveyID'
    ),
    $$ values (false, 2::bigint, 'ready', true) $$,
    'Should store undated drafts as ready with a bumped revision'
);

-- Should mark drafts ready when the opening time matches at whole seconds
select lives_ok(
    format(
        $$select change_event_survey_status(%L::uuid, %L::uuid, %L::uuid, %L::uuid, 1, '2099-01-01 12:00:00.700+00'::timestamptz, 'mark-ready')$$,
        :'actorUserID', :'groupID', :'futureEventID', :'markReadyFutureSurveyID'
    ),
    'Should mark drafts ready when the opening time matches at whole seconds'
);
select results_eq(
    format(
        $$
            select s.closed_at is not null, s.revision, s.status, s.updated_at is not null
            from event_survey s
            where s.event_survey_id = %L
        $$,
        :'markReadyFutureSurveyID'
    ),
    $$ values (false, 2::bigint, 'ready', true) $$,
    'Should store future drafts as ready with a bumped revision'
);

-- Should move scheduled surveys back to draft
select lives_ok(
    format(
        $$select change_event_survey_status(%L::uuid, %L::uuid, %L::uuid, %L::uuid, 1, null::timestamptz, 'back-to-draft')$$,
        :'actorUserID', :'groupID', :'futureEventID', :'scheduledSurveyID'
    ),
    'Should move scheduled surveys back to draft'
);
select results_eq(
    format(
        $$
            select s.closed_at is not null, s.revision, s.status, s.updated_at is not null
            from event_survey s
            where s.event_survey_id = %L
        $$,
        :'scheduledSurveyID'
    ),
    $$ values (false, 2::bigint, 'draft', true) $$,
    'Should store the draft status with a bumped revision'
);

-- Should reject back to draft for answered surveys
select throws_ok(
    format(
        $$select change_event_survey_status(%L::uuid, %L::uuid, %L::uuid, %L::uuid, 1, null::timestamptz, 'back-to-draft')$$,
        :'actorUserID', :'groupID', :'futureEventID', :'answeredScheduledSurveyID'
    ),
    'OCG01',
    'only scheduled surveys not yet sent or answered can move back to draft',
    'Should reject back to draft for answered surveys'
);

-- Should reject back to draft for open surveys
select throws_ok(
    format(
        $$select change_event_survey_status(%L::uuid, %L::uuid, %L::uuid, %L::uuid, 1, null::timestamptz, 'back-to-draft')$$,
        :'actorUserID', :'groupID', :'pastEventID', :'openRejectSurveyID'
    ),
    'OCG01',
    'only scheduled surveys not yet sent or answered can move back to draft',
    'Should reject back to draft for open surveys'
);

-- Should reject back to draft once the opening email was processed
select throws_ok(
    format(
        $$select change_event_survey_status(%L::uuid, %L::uuid, %L::uuid, %L::uuid, 1, null::timestamptz, 'back-to-draft')$$,
        :'actorUserID', :'groupID', :'futureEventID', :'processedScheduledSurveyID'
    ),
    'OCG01',
    'only scheduled surveys not yet sent or answered can move back to draft',
    'Should reject back to draft once the opening email was processed'
);

-- Should reject canceled events
select throws_ok(
    format(
        $$select change_event_survey_status(%L::uuid, %L::uuid, %L::uuid, %L::uuid, 1, null::timestamptz, 'close')$$,
        :'actorUserID', :'groupID', :'canceledEventID', :'canceledEventSurveyID'
    ),
    'OCG01',
    'event not found or inactive',
    'Should reject canceled events'
);

-- Should reject closing surveys that are not open
select throws_ok(
    format(
        $$select change_event_survey_status(%L::uuid, %L::uuid, %L::uuid, %L::uuid, 1, null::timestamptz, 'close')$$,
        :'actorUserID', :'groupID', :'futureEventID', :'processedScheduledSurveyID'
    ),
    'OCG01',
    'only open surveys can be closed',
    'Should reject closing surveys that are not open'
);

-- Should reject invalid actions
select throws_ok(
    format(
        $$select change_event_survey_status(%L::uuid, %L::uuid, %L::uuid, %L::uuid, 1, null::timestamptz, 'publish')$$,
        :'actorUserID', :'groupID', :'pastEventID', :'openRejectSurveyID'
    ),
    'OCG01',
    'invalid event survey status action',
    'Should reject invalid actions'
);

-- Should reject mark ready for surveys that are not drafts
select throws_ok(
    format(
        $$select change_event_survey_status(%L::uuid, %L::uuid, %L::uuid, %L::uuid, 1, '2025-01-02 00:00:00+00'::timestamptz, 'mark-ready')$$,
        :'actorUserID', :'groupID', :'pastEventID', :'openRejectSurveyID'
    ),
    'OCG01',
    'only draft surveys can be marked ready',
    'Should reject mark ready for surveys that are not drafts'
);

-- Should reject mark ready for surveys without questions
select throws_ok(
    format(
        $$select change_event_survey_status(%L::uuid, %L::uuid, %L::uuid, %L::uuid, 1, '2025-01-02 00:00:00+00'::timestamptz, 'mark-ready')$$,
        :'actorUserID', :'groupID', :'pastEventID', :'emptyDraftSurveyID'
    ),
    'OCG01',
    'event survey must have at least one question',
    'Should reject mark ready for surveys without questions'
);

-- Should reject mark ready when the event got dates
select throws_ok(
    format(
        $$select change_event_survey_status(%L::uuid, %L::uuid, %L::uuid, %L::uuid, 1, null::timestamptz, 'mark-ready')$$,
        :'actorUserID', :'groupID', :'futureEventID', :'datedMismatchSurveyID'
    ),
    'OCG01',
    'the survey opening time changed; review and try again',
    'Should reject mark ready when the event got dates'
);

-- Should reject mark ready when the event lost its dates
select throws_ok(
    format(
        $$select change_event_survey_status(%L::uuid, %L::uuid, %L::uuid, %L::uuid, 1, '2025-01-01 12:00:00+00'::timestamptz, 'mark-ready')$$,
        :'actorUserID', :'groupID', :'undatedEventID', :'undatedMismatchSurveyID'
    ),
    'OCG01',
    'the survey opening time changed; review and try again',
    'Should reject mark ready when the event lost its dates'
);

-- Should reject mark ready when the opening time changed
select throws_ok(
    format(
        $$select change_event_survey_status(%L::uuid, %L::uuid, %L::uuid, %L::uuid, 1, '2098-12-31 12:00:00+00'::timestamptz, 'mark-ready')$$,
        :'actorUserID', :'groupID', :'futureEventID', :'rescheduledSurveyID'
    ),
    'OCG01',
    'the survey opening time changed; review and try again',
    'Should reject mark ready when the opening time changed'
);

-- Should reject mark ready with a past opening for surveys opening in the future
select throws_ok(
    format(
        $$select change_event_survey_status(%L::uuid, %L::uuid, %L::uuid, %L::uuid, 1, '2025-01-02 00:00:00+00'::timestamptz, 'mark-ready')$$,
        :'actorUserID', :'groupID', :'futureEventID', :'pastConfirmationSurveyID'
    ),
    'OCG01',
    'the survey opening time changed; review and try again',
    'Should reject mark ready with a past opening for surveys opening in the future'
);

-- Should reject reopening surveys past their closing date
select throws_ok(
    format(
        $$select change_event_survey_status(%L::uuid, %L::uuid, %L::uuid, %L::uuid, 1, null::timestamptz, 'reopen')$$,
        :'actorUserID', :'groupID', :'pastEventID', :'expiredSurveyID'
    ),
    'OCG01',
    'the survey closing date has passed; edit it to reopen the survey',
    'Should reject reopening surveys past their closing date'
);

-- Should reject reopening surveys that are not closed
select throws_ok(
    format(
        $$select change_event_survey_status(%L::uuid, %L::uuid, %L::uuid, %L::uuid, 1, null::timestamptz, 'reopen')$$,
        :'actorUserID', :'groupID', :'pastEventID', :'openRejectSurveyID'
    ),
    'OCG01',
    'only closed surveys can be reopened',
    'Should reject reopening surveys that are not closed'
);

-- Should reject stale revisions
select throws_ok(
    format(
        $$select change_event_survey_status(%L::uuid, %L::uuid, %L::uuid, %L::uuid, 5, null::timestamptz, 'close')$$,
        :'actorUserID', :'groupID', :'pastEventID', :'openRejectSurveyID'
    ),
    'OCG01',
    'the survey changed; review and try again',
    'Should reject stale revisions'
);

-- Should reject surveys of another event
select throws_ok(
    format(
        $$select change_event_survey_status(%L::uuid, %L::uuid, %L::uuid, %L::uuid, 1, null::timestamptz, 'close')$$,
        :'actorUserID', :'groupID', :'pastEventID', :'otherEventSurveyID'
    ),
    'OCG01',
    'event survey not found',
    'Should reject surveys of another event'
);

-- Should reopen closed surveys
select lives_ok(
    format(
        $$select change_event_survey_status(%L::uuid, %L::uuid, %L::uuid, %L::uuid, 1, null::timestamptz, 'reopen')$$,
        :'actorUserID', :'groupID', :'pastEventID', :'closedSurveyID'
    ),
    'Should reopen closed surveys'
);
select results_eq(
    format(
        $$
            select s.closed_at is not null, s.revision, s.status, s.updated_at is not null
            from event_survey s
            where s.event_survey_id = %L
        $$,
        :'closedSurveyID'
    ),
    $$ values (false, 2::bigint, 'ready', true) $$,
    'Should clear the manual close with a bumped revision'
);

-- Should reopen closed surveys without a closing date
select lives_ok(
    format(
        $$select change_event_survey_status(%L::uuid, %L::uuid, %L::uuid, %L::uuid, 1, null::timestamptz, 'reopen')$$,
        :'actorUserID', :'groupID', :'pastEventID', :'closedUndatedSurveyID'
    ),
    'Should reopen closed surveys without a closing date'
);
select results_eq(
    format(
        $$
            select s.closed_at is not null, s.revision, s.status, s.updated_at is not null
            from event_survey s
            where s.event_survey_id = %L
        $$,
        :'closedUndatedSurveyID'
    ),
    $$ values (false, 2::bigint, 'ready', true) $$,
    'Should clear the manual close of surveys without a closing date'
);

-- Should track every successful transition in the audit log
select results_eq(
    format(
        $$
            select
                al.action,
                al.actor_user_id,
                al.community_id,
                al.details,
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
                ('event_survey_reopened', %L::uuid, %L::uuid, '{"title": "Closed survey"}'::jsonb, %L::uuid, %L::uuid, 'event_survey'),
                ('event_survey_marked_ready', %L::uuid, %L::uuid, '{"title": "Future draft survey"}'::jsonb, %L::uuid, %L::uuid, 'event_survey'),
                ('event_survey_marked_ready', %L::uuid, %L::uuid, '{"title": "Past draft survey"}'::jsonb, %L::uuid, %L::uuid, 'event_survey'),
                ('event_survey_marked_ready', %L::uuid, %L::uuid, '{"title": "Undated draft survey"}'::jsonb, %L::uuid, %L::uuid, 'event_survey'),
                ('event_survey_closed', %L::uuid, %L::uuid, '{"title": "Open survey to close"}'::jsonb, %L::uuid, %L::uuid, 'event_survey'),
                ('event_survey_moved_to_draft', %L::uuid, %L::uuid, '{"title": "Scheduled survey"}'::jsonb, %L::uuid, %L::uuid, 'event_survey'),
                ('event_survey_reopened', %L::uuid, %L::uuid, '{"title": "Closed survey without closing date"}'::jsonb, %L::uuid, %L::uuid, 'event_survey')
        $$,
        :'actorUserID', :'communityID', :'groupID', :'closedSurveyID',
        :'actorUserID', :'communityID', :'groupID', :'markReadyFutureSurveyID',
        :'actorUserID', :'communityID', :'groupID', :'markReadyPastSurveyID',
        :'actorUserID', :'communityID', :'groupID', :'markReadyUndatedSurveyID',
        :'actorUserID', :'communityID', :'groupID', :'openCloseSurveyID',
        :'actorUserID', :'communityID', :'groupID', :'scheduledSurveyID',
        :'actorUserID', :'communityID', :'groupID', :'closedUndatedSurveyID'
    ),
    'Should track every successful transition in the audit log'
);

-- Should walk a survey through mark ready, close, reopen and close

-- Mark the draft ready, opening it at once
select lives_ok(
    format(
        $$select change_event_survey_status(%L::uuid, %L::uuid, %L::uuid, %L::uuid, 1, '2025-01-02 00:00:00+00'::timestamptz, 'mark-ready')$$,
        :'actorUserID', :'lifecycleGroupID', :'lifecycleEventID', :'lifecycleSurveyID'
    ),
    'Should mark the lifecycle survey ready'
);
select results_eq(
    format(
        $$
            select s.closed_at is not null, s.revision, s.status
            from event_survey s
            where s.event_survey_id = %L
        $$,
        :'lifecycleSurveyID'
    ),
    $$ values (false, 2::bigint, 'ready') $$,
    'Should store the lifecycle survey as ready and open'
);

-- Close the open survey
select lives_ok(
    format(
        $$select change_event_survey_status(%L::uuid, %L::uuid, %L::uuid, %L::uuid, 2, null::timestamptz, 'close')$$,
        :'actorUserID', :'lifecycleGroupID', :'lifecycleEventID', :'lifecycleSurveyID'
    ),
    'Should close the lifecycle survey'
);
select results_eq(
    format(
        $$
            select s.closed_at is not null, s.revision, s.status
            from event_survey s
            where s.event_survey_id = %L
        $$,
        :'lifecycleSurveyID'
    ),
    $$ values (true, 3::bigint, 'ready') $$,
    'Should store the first manual close of the lifecycle survey'
);

-- Reopen the closed survey
select lives_ok(
    format(
        $$select change_event_survey_status(%L::uuid, %L::uuid, %L::uuid, %L::uuid, 3, null::timestamptz, 'reopen')$$,
        :'actorUserID', :'lifecycleGroupID', :'lifecycleEventID', :'lifecycleSurveyID'
    ),
    'Should reopen the lifecycle survey'
);
select results_eq(
    format(
        $$
            select s.closed_at is not null, s.revision, s.status
            from event_survey s
            where s.event_survey_id = %L
        $$,
        :'lifecycleSurveyID'
    ),
    $$ values (false, 4::bigint, 'ready') $$,
    'Should clear the manual close of the lifecycle survey'
);

-- Close the reopened survey again
select lives_ok(
    format(
        $$select change_event_survey_status(%L::uuid, %L::uuid, %L::uuid, %L::uuid, 4, null::timestamptz, 'close')$$,
        :'actorUserID', :'lifecycleGroupID', :'lifecycleEventID', :'lifecycleSurveyID'
    ),
    'Should close the reopened lifecycle survey'
);
select results_eq(
    format(
        $$
            select s.closed_at is not null, s.revision, s.status
            from event_survey s
            where s.event_survey_id = %L
        $$,
        :'lifecycleSurveyID'
    ),
    $$ values (true, 5::bigint, 'ready') $$,
    'Should store the second manual close of the lifecycle survey'
);

-- Check every transition was audited
select results_eq(
    format(
        $$
            select al.action, count(*)::int
            from audit_log al
            where al.resource_id = %L
            group by al.action
            order by al.action
        $$,
        :'lifecycleSurveyID'
    ),
    $$
        values
            ('event_survey_closed', 2),
            ('event_survey_marked_ready', 1),
            ('event_survey_reopened', 1)
    $$,
    'Should audit every transition of the lifecycle survey'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
