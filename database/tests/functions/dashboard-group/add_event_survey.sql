-- Tests adding surveys to group events.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorUserID 'a5e00013-0000-0000-0000-000000000001'
\set almostFullEventID 'a5e00013-0000-0000-0000-00000000000b'
\set almostFullGroupID 'a5e00013-0000-0000-0000-00000000000c'
\set canceledEventID 'a5e00013-0000-0000-0000-000000000002'
\set communityID 'a5e00013-0000-0000-0000-000000000003'
\set eventCategoryID 'a5e00013-0000-0000-0000-000000000004'
\set eventID 'a5e00013-0000-0000-0000-000000000005'
\set foreignGroupID 'a5e00013-0000-0000-0000-000000000006'
\set fullEventID 'a5e00013-0000-0000-0000-000000000007'
\set groupCategoryID 'a5e00013-0000-0000-0000-000000000008'
\set groupID 'a5e00013-0000-0000-0000-000000000009'
\set questionID 'a5e00013-0000-0000-0000-00000000000a'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community hosting the surveyed events
select fx_community(:'communityID');

-- Organizer adding the surveys
select fx_user(:'actorUserID');

-- Event category used by the surveyed events
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category used by the groups
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group hosting the event that reaches the survey limit
select fx_group(:'almostFullGroupID', :'communityID', :'groupCategoryID');

-- Group that does not own the surveyed events
select fx_group(:'foreignGroupID', :'communityID', :'groupCategoryID');

-- Group hosting the surveyed events
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event that has one survey less than the maximum
select fx_event(:'almostFullEventID', :'almostFullGroupID', :'eventCategoryID');

-- Canceled event whose surveys cannot be managed
select fx_event(:'canceledEventID', :'groupID', :'eventCategoryID', jsonb_build_object('canceled', true));

-- Event in Madrid receiving the new survey
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('timezone', 'Europe/Madrid'));

-- Event that already has the maximum number of surveys
select fx_event(:'fullEventID', :'groupID', :'eventCategoryID');

-- Nine surveys of the event that has room for one more
insert into event_survey (event_id, title)
select :'almostFullEventID'::uuid, 'Survey ' || n
from generate_series(1, 9) as n;

-- Ten surveys filling the full event
insert into event_survey (event_id, title)
select :'fullEventID'::uuid, 'Survey ' || n
from generate_series(1, 10) as n;

-- ============================================================================
-- TESTS
-- ============================================================================

-- Add a survey with padded text and local dates
select add_event_survey(
    :'actorUserID'::uuid,
    :'groupID'::uuid,
    :'eventID'::uuid,
    jsonb_build_object(
        'anonymous', false,
        'audience', 'checked-in',
        'closes_at', '2025-02-08T10:00:00',
        'description', '  Tell us how it went  ',
        'opens_at', '2025-02-01T10:00:00',
        'questions', jsonb_build_array(jsonb_build_object(
            'id', :'questionID'::uuid,
            'kind', 'free-text',
            'prompt', 'Feedback',
            'required', false
        )),
        'title', '  Feedback  '
    )
) as "addedSurveyID" \gset

-- Should add a draft survey with normalized settings
select results_eq(
    format(
        $$
            select
                s.anonymous,
                s.audience,
                s.event_id,
                s.questions,
                s.revision,
                s.status,
                s.title,

                s.closes_at,
                s.created_by,
                s.description,
                s.opens_at
            from event_survey s
            where s.event_survey_id = %L
        $$,
        :'addedSurveyID'
    ),
    format(
        $$
            values (
                false,
                'checked-in',
                %L::uuid,
                jsonb_build_array(jsonb_build_object(
                    'id', %L::uuid,
                    'kind', 'free-text',
                    'prompt', 'Feedback',
                    'required', false
                )),
                1::bigint,
                'draft',
                'Feedback',

                '2025-02-08 09:00:00+00'::timestamptz,
                %L::uuid,
                'Tell us how it went',
                '2025-02-01 09:00:00+00'::timestamptz
            )
        $$,
        :'eventID', :'questionID', :'actorUserID'
    ),
    'Should add a draft survey with normalized settings'
);

-- Should add the tenth survey of an event
select lives_ok(
    format(
        $$select add_event_survey(%L::uuid, %L::uuid, %L::uuid, '{"anonymous": true, "audience": "confirmed", "questions": [], "title": "Tenth survey"}'::jsonb)$$,
        :'actorUserID', :'almostFullGroupID', :'almostFullEventID'
    ),
    'Should add the tenth survey of an event'
);
select is(
    (select count(*)::int from event_survey where event_id = :'almostFullEventID'),
    10,
    'Should store the tenth survey of an event'
);

-- Should record only the successful addition in the audit log
select results_eq(
    format(
        $$
            select
                al.action,
                al.actor_user_id,
                al.community_id,
                al.details,
                al.event_id,
                al.group_id,
                al.resource_id,
                al.resource_type
            from audit_log al
            where al.group_id = %L
        $$,
        :'groupID'
    ),
    format(
        $$
            values (
                'event_survey_added',
                %L::uuid,
                %L::uuid,
                '{"title": "Feedback"}'::jsonb,
                %L::uuid,
                %L::uuid,
                %L::uuid,
                'event_survey'
            )
        $$,
        :'actorUserID', :'communityID', :'eventID', :'groupID', :'addedSurveyID'
    ),
    'Should record only the successful addition in the audit log'
);

-- Should reject canceled events
select throws_ok(
    format(
        $$select add_event_survey(%L::uuid, %L::uuid, %L::uuid, '{"anonymous": true, "audience": "confirmed", "questions": [], "title": "Survey"}'::jsonb)$$,
        :'actorUserID', :'groupID', :'canceledEventID'
    ),
    'OCG01',
    'event not found or inactive',
    'Should reject canceled events'
);

-- Should reject events of another group
select throws_ok(
    format(
        $$select add_event_survey(%L::uuid, %L::uuid, %L::uuid, '{"anonymous": true, "audience": "confirmed", "questions": [], "title": "Survey"}'::jsonb)$$,
        :'actorUserID', :'foreignGroupID', :'eventID'
    ),
    'OCG01',
    'event not found or inactive',
    'Should reject events of another group'
);

-- Should reject events that already have 10 surveys
select throws_ok(
    format(
        $$select add_event_survey(%L::uuid, %L::uuid, %L::uuid, '{"anonymous": true, "audience": "confirmed", "questions": [], "title": "Survey"}'::jsonb)$$,
        :'actorUserID', :'groupID', :'fullEventID'
    ),
    'OCG01',
    'events can have up to 10 surveys',
    'Should reject events that already have 10 surveys'
);

-- Should reject invalid payloads
select throws_ok(
    format(
        $$select add_event_survey(%L::uuid, %L::uuid, %L::uuid, '{"anonymous": true, "audience": "confirmed", "questions": [], "title": " "}'::jsonb)$$,
        :'actorUserID', :'groupID', :'eventID'
    ),
    'OCG01',
    'event survey title is required',
    'Should reject invalid payloads'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
