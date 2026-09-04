-- Tests detecting questionnaire answers for events.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set attendeeUserID '0c030000-0000-0000-0000-000000000001'
\set communityID '0c030000-0000-0000-0000-000000000002'
\set eventAttendeeAnswersID '0c030000-0000-0000-0000-000000000003'
\set eventAttendeeNullAnswersID '0c030000-0000-0000-0000-000000000004'
\set eventCategoryID '0c030000-0000-0000-0000-000000000005'
\set eventNoAnswersID '0c030000-0000-0000-0000-000000000006'
\set eventRequestAnswersID '0c030000-0000-0000-0000-000000000007'
\set groupCategoryID '0c030000-0000-0000-0000-000000000008'
\set groupID '0c030000-0000-0000-0000-000000000009'
\set nullAnswersUserID '0c030000-0000-0000-0000-00000000000a'
\set requestTicketTypeID '0c030000-0000-0000-0000-00000000000c'
\set requestUserID '0c030000-0000-0000-0000-00000000000b'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories, event categories, users, groups and events
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'requestUserID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_event(:'eventNoAnswersID', :'groupID', :'eventCategoryID');
select fx_event(:'eventAttendeeAnswersID', :'groupID', :'eventCategoryID');
select fx_event(:'eventAttendeeNullAnswersID', :'groupID', :'eventCategoryID');
select fx_event(:'eventRequestAnswersID', :'groupID', :'eventCategoryID');

-- Users
select fx_user(:'attendeeUserID', jsonb_build_object('username', 'attendee'));
select fx_user(:'nullAnswersUserID', jsonb_build_object('username', 'null-answers'));

-- Admission tier associated with the invitation request answers
select fx_event_ticket_type(:'requestTicketTypeID', :'eventRequestAnswersID', jsonb_build_object('seats_total', 10));

-- Attendee answers
insert into event_attendee (event_id, user_id, registration_answers)
values
    (:'eventAttendeeAnswersID', :'attendeeUserID', '{"answers": []}'::jsonb),
    (:'eventAttendeeNullAnswersID', :'nullAnswersUserID', null);

-- Invitation request answers
insert into event_invitation_request (
    event_id,
    event_ticket_type_id,
    user_id,
    registration_answers
)
values (
    :'eventRequestAnswersID',
    :'requestTicketTypeID',
    :'requestUserID',
    '{"answers": []}'::jsonb
);

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
