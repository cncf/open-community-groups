-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set attendeeUserID '0c150000-0000-0000-0000-000000000001'
\set allianceID '0c150000-0000-0000-0000-000000000002'
\set eventAttendeeAnswersID '0c150000-0000-0000-0000-000000000003'
\set eventAttendeeNullAnswersID '0c150000-0000-0000-0000-000000000004'
\set eventCategoryID '0c150000-0000-0000-0000-000000000005'
\set eventNoAnswersID '0c150000-0000-0000-0000-000000000006'
\set eventRequestAnswersID '0c150000-0000-0000-0000-000000000007'
\set groupCategoryID '0c150000-0000-0000-0000-000000000008'
\set groupID '0c150000-0000-0000-0000-000000000009'
\set nullAnswersUserID '0c150000-0000-0000-0000-00000000000a'
\set requestUserID '0c150000-0000-0000-0000-00000000000b'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'allianceID',
    'questionnaire-alliance',
    'Questionnaire Alliance',
    'Alliance for questionnaire answer tests',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, alliance_id, name)
values (:'groupCategoryID', :'allianceID', 'Technology');

-- Event category
insert into event_category (event_category_id, alliance_id, name)
values (:'eventCategoryID', :'allianceID', 'General');

-- Group
insert into "group" (group_id, alliance_id, group_category_id, name, slug)
values (
    :'groupID',
    :'allianceID',
    :'groupCategoryID',
    'Questionnaire Group',
    'questionnaire-group'
);

-- Users
insert into "user" (user_id, auth_hash, email, email_verified, username)
values
    (:'attendeeUserID', 'hash-1', 'attendee@example.com', true, 'attendee'),
    (:'nullAnswersUserID', 'hash-3', 'null-answers@example.com', true, 'null-answers'),
    (:'requestUserID', 'hash-2', 'request@example.com', true, 'requester');

-- Events
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id
) values (
    :'eventNoAnswersID',
    :'groupID',
    'No Answers Event',
    'no-answers-event',
    'Event without registration answers',
    'UTC',
    :'eventCategoryID',
    'in-person'
), (
    :'eventAttendeeAnswersID',
    :'groupID',
    'Attendee Answers Event',
    'attendee-answers-event',
    'Event with attendee answers',
    'UTC',
    :'eventCategoryID',
    'in-person'
), (
    :'eventAttendeeNullAnswersID',
    :'groupID',
    'Attendee Null Answers Event',
    'attendee-null-answers-event',
    'Event with null attendee answers',
    'UTC',
    :'eventCategoryID',
    'in-person'
), (
    :'eventRequestAnswersID',
    :'groupID',
    'Request Answers Event',
    'request-answers-event',
    'Event with invitation request answers',
    'UTC',
    :'eventCategoryID',
    'in-person'
);

-- Attendee answers
insert into event_attendee (event_id, user_id, registration_answers)
values
    (:'eventAttendeeAnswersID', :'attendeeUserID', '{"answers": []}'::jsonb),
    (:'eventAttendeeNullAnswersID', :'nullAnswersUserID', null);

-- Invitation request answers
insert into event_invitation_request (event_id, user_id, registration_answers)
values (:'eventRequestAnswersID', :'requestUserID', '{"answers": []}'::jsonb);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return false when no answers exist
select is(
    questionnaire_answers_exist_for_event(:'eventNoAnswersID'::uuid),
    false,
    'Should return false when no answers exist'
);

-- Should return true when attendee answers exist
select is(
    questionnaire_answers_exist_for_event(:'eventAttendeeAnswersID'::uuid),
    true,
    'Should return true when attendee answers exist'
);

-- Should ignore attendee rows that have no registration answers
select is(
    questionnaire_answers_exist_for_event(:'eventAttendeeNullAnswersID'::uuid),
    false,
    'Should ignore attendee rows with null registration answers'
);

-- Should return true when invitation request answers exist
select is(
    questionnaire_answers_exist_for_event(:'eventRequestAnswersID'::uuid),
    true,
    'Should return true when invitation request answers exist'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
