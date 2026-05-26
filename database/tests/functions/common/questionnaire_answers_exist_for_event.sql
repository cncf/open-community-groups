-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set attendeeUserID '90100000-0000-0000-0000-000000000031'
\set categoryID '90100000-0000-0000-0000-000000000011'
\set communityID '90100000-0000-0000-0000-000000000001'
\set eventCategoryID '90100000-0000-0000-0000-000000000012'
\set eventAttendeeAnswersID '90100000-0000-0000-0000-000000000042'
\set eventAttendeeNullAnswersID '90100000-0000-0000-0000-000000000044'
\set eventNoAnswersID '90100000-0000-0000-0000-000000000041'
\set eventRequestAnswersID '90100000-0000-0000-0000-000000000043'
\set groupID '90100000-0000-0000-0000-000000000021'
\set nullAnswersUserID '90100000-0000-0000-0000-000000000033'
\set requestUserID '90100000-0000-0000-0000-000000000032'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'questionnaire-community', 'Questionnaire Community', 'Desc', 'https://example.com/logo.png', 'https://example.com/banner-mobile.png', 'https://example.com/banner.png');

-- Group category
insert into group_category (group_category_id, name, community_id)
values (:'categoryID', 'Technology', :'communityID');

-- Event category
insert into event_category (event_category_id, name, community_id)
values (:'eventCategoryID', 'General', :'communityID');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'categoryID', 'Questionnaire Group', 'questionnaire-group');

-- Users
insert into "user" (user_id, auth_hash, email, username)
values
    (:'attendeeUserID', 'hash-1', 'attendee@example.com', 'attendee'),
    (:'nullAnswersUserID', 'hash-3', 'null-answers@example.com', 'null-answers'),
    (:'requestUserID', 'hash-2', 'request@example.com', 'requester');

-- Events
insert into event (event_id, group_id, name, slug, description, timezone, event_category_id, event_kind_id)
values
    (:'eventNoAnswersID', :'groupID', 'No Answers Event', 'no-answers-event', 'Desc', 'UTC', :'eventCategoryID', 'in-person'),
    (:'eventAttendeeAnswersID', :'groupID', 'Attendee Answers Event', 'attendee-answers-event', 'Desc', 'UTC', :'eventCategoryID', 'in-person'),
    (:'eventAttendeeNullAnswersID', :'groupID', 'Attendee Null Answers Event', 'attendee-null-answers-event', 'Desc', 'UTC', :'eventCategoryID', 'in-person'),
    (:'eventRequestAnswersID', :'groupID', 'Request Answers Event', 'request-answers-event', 'Desc', 'UTC', :'eventCategoryID', 'in-person');

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
