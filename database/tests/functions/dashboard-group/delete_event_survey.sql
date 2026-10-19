-- Tests deleting surveys of group events.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorUserID 'a5e00015-0000-0000-0000-000000000001'
\set canceledEventID 'a5e00015-0000-0000-0000-000000000002'
\set canceledEventSurveyID 'a5e00015-0000-0000-0000-000000000003'
\set communityID 'a5e00015-0000-0000-0000-000000000004'
\set eventCategoryID 'a5e00015-0000-0000-0000-000000000005'
\set eventID 'a5e00015-0000-0000-0000-000000000006'
\set firstRespondentID 'a5e00015-0000-0000-0000-000000000007'
\set groupCategoryID 'a5e00015-0000-0000-0000-000000000008'
\set groupID 'a5e00015-0000-0000-0000-000000000009'
\set keptSurveyID 'a5e00015-0000-0000-0000-00000000000e'
\set otherEventID 'a5e00015-0000-0000-0000-00000000000a'
\set otherEventSurveyID 'a5e00015-0000-0000-0000-00000000000b'
\set secondRespondentID 'a5e00015-0000-0000-0000-00000000000c'
\set surveyID 'a5e00015-0000-0000-0000-00000000000d'
\set unansweredSurveyID 'a5e00015-0000-0000-0000-00000000000f'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community hosting the surveyed events
select fx_community(:'communityID');

-- Organizer deleting the survey
select fx_user(:'actorUserID');

-- First user who answered the deleted survey
select fx_user(:'firstRespondentID');

-- Second user who answered the deleted survey
select fx_user(:'secondRespondentID');

-- Event category used by the surveyed events
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category used by the group
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group hosting the surveyed events
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Canceled event whose surveys cannot be managed
select fx_event(:'canceledEventID', :'groupID', :'eventCategoryID', jsonb_build_object('canceled', true));

-- Event owning the deleted surveys
select fx_event(:'eventID', :'groupID', :'eventCategoryID');

-- Event of the same group that does not own the deleted survey
select fx_event(:'otherEventID', :'groupID', :'eventCategoryID');

-- Survey of the canceled event
insert into event_survey (event_survey_id, event_id, title)
values (:'canceledEventSurveyID', :'canceledEventID', 'Canceled event survey');

-- Survey of the event kept when its other surveys are deleted
insert into event_survey (event_survey_id, event_id, title)
values (:'keptSurveyID', :'eventID', 'Kept survey');

-- Survey of another event of the group
insert into event_survey (event_survey_id, event_id, title)
values (:'otherEventSurveyID', :'otherEventID', 'Other event survey');

-- Answered survey deleted by the organizer
insert into event_survey (event_survey_id, event_id, status, title, first_response_at)
values (:'surveyID', :'eventID', 'ready', 'Deleted survey', '2025-01-02 10:00:00+00');

-- Survey without responses deleted by the organizer
insert into event_survey (event_survey_id, event_id, title)
values (:'unansweredSurveyID', :'eventID', 'Unanswered survey');

-- Response from the first respondent
insert into event_survey_response (answers, event_survey_id, user_id)
values ('{"answers": []}', :'surveyID', :'firstRespondentID');

-- Response from the second respondent
insert into event_survey_response (answers, event_survey_id, user_id)
values ('{"answers": []}', :'surveyID', :'secondRespondentID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should delete answered surveys
select lives_ok(
    format(
        $$select delete_event_survey(%L::uuid, %L::uuid, %L::uuid, %L::uuid)$$,
        :'actorUserID', :'groupID', :'eventID', :'surveyID'
    ),
    'Should delete answered surveys'
);

-- Should delete the survey together with its responses
select is(
    (
        select jsonb_build_object(
            'responses', (
                select count(*)
                from event_survey_response r
                where r.event_survey_id = :'surveyID'
            ),
            'surveys', (
                select count(*)
                from event_survey s
                where s.event_survey_id = :'surveyID'
            )
        )
    ),
    '{"responses": 0, "surveys": 0}'::jsonb,
    'Should delete the survey together with its responses'
);

-- Should record the deletion with the title and the response count
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
                'event_survey_deleted',
                %L::uuid,
                %L::uuid,
                '{"responses_count": 2, "title": "Deleted survey"}'::jsonb,
                %L::uuid,
                %L::uuid,
                %L::uuid,
                'event_survey'
            )
        $$,
        :'actorUserID', :'communityID', :'eventID', :'groupID', :'surveyID'
    ),
    'Should record the deletion with the title and the response count'
);

-- Should delete surveys without responses
select lives_ok(
    format(
        $$select delete_event_survey(%L::uuid, %L::uuid, %L::uuid, %L::uuid)$$,
        :'actorUserID', :'groupID', :'eventID', :'unansweredSurveyID'
    ),
    'Should delete surveys without responses'
);

-- Should remove the survey without responses
select is(
    (select count(*) from event_survey s where s.event_survey_id = :'unansweredSurveyID'),
    0::bigint,
    'Should remove the survey without responses'
);

-- Should keep the other surveys of the event
select results_eq(
    format(
        $$select s.event_survey_id from event_survey s where s.event_id = %L$$,
        :'eventID'
    ),
    format($$values (%L::uuid)$$, :'keptSurveyID'),
    'Should keep the other surveys of the event'
);

-- Should reject canceled events
select throws_ok(
    format(
        $$select delete_event_survey(%L::uuid, %L::uuid, %L::uuid, %L::uuid)$$,
        :'actorUserID', :'groupID', :'canceledEventID', :'canceledEventSurveyID'
    ),
    'OCG01',
    'event not found or inactive',
    'Should reject canceled events'
);

-- Should reject surveys of another event
select throws_ok(
    format(
        $$select delete_event_survey(%L::uuid, %L::uuid, %L::uuid, %L::uuid)$$,
        :'actorUserID', :'groupID', :'eventID', :'otherEventSurveyID'
    ),
    'OCG01',
    'event survey not found',
    'Should reject surveys of another event'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
