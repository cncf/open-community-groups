-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(11);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '90200000-0000-0000-0000-000000000011'
\set communityID '90200000-0000-0000-0000-000000000001'
\set eventCategoryID '90200000-0000-0000-0000-000000000012'
\set eventID '90200000-0000-0000-0000-000000000041'
\set eventStartedID '90200000-0000-0000-0000-000000000042'
\set eventNoQuestionsID '90200000-0000-0000-0000-000000000043'
\set eventTicketedID '90200000-0000-0000-0000-000000000044'
\set eventTicketTypeID '90200000-0000-0000-0000-000000000051'
\set groupID '90200000-0000-0000-0000-000000000021'
\set nonAttendeeUserID '90200000-0000-0000-0000-000000000034'
\set pendingUserID '90200000-0000-0000-0000-000000000031'
\set pendingPurchaseID '90200000-0000-0000-0000-000000000061'
\set priceWindowID '90200000-0000-0000-0000-000000000052'
\set ticketedPendingUserID '90200000-0000-0000-0000-000000000035'
\set updateUserID '90200000-0000-0000-0000-000000000032'
\set startedEventUserID '90200000-0000-0000-0000-000000000033'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'answers-community', 'Answers Community', 'Desc', 'https://example.com/logo.png', 'https://example.com/banner-mobile.png', 'https://example.com/banner.png');

-- Group category
insert into group_category (group_category_id, name, community_id)
values (:'categoryID', 'Technology', :'communityID');

-- Event category
insert into event_category (event_category_id, name, community_id)
values (:'eventCategoryID', 'General', :'communityID');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'categoryID', 'Answers Group', 'answers-group');

-- Users
insert into "user" (user_id, auth_hash, email, username)
values
    (:'pendingUserID', 'hash-1', 'pending@example.com', 'pending-user'),
    (:'updateUserID', 'hash-2', 'update@example.com', 'update-user'),
    (:'startedEventUserID', 'hash-3', 'started-event@example.com', 'started-event-user'),
    (:'nonAttendeeUserID', 'hash-4', 'non-attendee@example.com', 'non-attendee'),
    (:'ticketedPendingUserID', 'hash-5', 'ticketed-pending@example.com', 'ticketed-pending');

-- Events
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    published,
    starts_at,
    payment_currency_code,
    registration_questions
) values (
    :'eventID',
    :'groupID',
    'Answers Event',
    'answers-event',
    'Desc',
    'UTC',
    :'eventCategoryID',
    'in-person',
    true,
    now() + interval '1 day',
    null,
    '[{"id": "90200000-0000-0000-0000-000000000101", "kind": "single-select", "prompt": "Meal", "required": true, "options": [{"id": "90200000-0000-0000-0000-000000000201", "label": "Standard"}, {"id": "90200000-0000-0000-0000-000000000202", "label": "Vegetarian"}]}]'::jsonb
), (
    :'eventStartedID',
    :'groupID',
    'Started Event',
    'started-event',
    'Desc',
    'UTC',
    :'eventCategoryID',
    'in-person',
    true,
    now() - interval '1 hour',
    null,
    '[{"id": "90200000-0000-0000-0000-000000000101", "kind": "free-text", "prompt": "Note", "required": true, "options": []}]'::jsonb
), (
    :'eventNoQuestionsID',
    :'groupID',
    'No Questions Event',
    'no-questions-event',
    'Desc',
    'UTC',
    :'eventCategoryID',
    'in-person',
    true,
    now() + interval '7 days',
    null,
    '[]'::jsonb
), (
    :'eventTicketedID',
    :'groupID',
    'Ticketed Answers Event',
    'ticketed-answers-event',
    'Desc',
    'UTC',
    :'eventCategoryID',
    'in-person',
    true,
    now() + interval '2 days',
    'USD',
    '[{"id": "90200000-0000-0000-0000-000000000101", "kind": "single-select", "prompt": "Meal", "required": true, "options": [{"id": "90200000-0000-0000-0000-000000000201", "label": "Standard"}, {"id": "90200000-0000-0000-0000-000000000202", "label": "Vegetarian"}]}]'::jsonb
);

-- Event tickets
insert into event_ticket_type (event_ticket_type_id, event_id, "order", seats_total, title)
values (:'eventTicketTypeID', :'eventTicketedID', 1, 10, 'General admission');

-- Ticket price windows
insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values (
    :'priceWindowID',
    1000,
    :'eventTicketTypeID'
);

-- Event attendees
insert into event_attendee (event_id, user_id, registration_answers, status)
values
    (:'eventID', :'pendingUserID', null, 'registration-questions-pending'),
    (:'eventID', :'updateUserID', '{"answers": [{"question_id": "90200000-0000-0000-0000-000000000101", "value": "90200000-0000-0000-0000-000000000201"}]}'::jsonb, 'confirmed'),
    (:'eventStartedID', :'startedEventUserID', '{"answers": [{"question_id": "90200000-0000-0000-0000-000000000101", "value": "Initial"}]}'::jsonb, 'confirmed'),
    (:'eventNoQuestionsID', :'pendingUserID', null, 'confirmed'),
    (:'eventTicketedID', :'ticketedPendingUserID', null, 'registration-questions-pending');

-- Event purchases
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    currency_code,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    status,
    ticket_title,
    user_id
) values (
    :'pendingPurchaseID',
    1000,
    'USD',
    :'eventTicketedID',
    :'eventTicketTypeID',
    now() + interval '10 minutes',
    'pending',
    'General admission',
    :'ticketedPendingUserID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should report pending attendance became confirmed after answers are submitted
select results_eq(
    $$
        select submit_event_registration_answers(
            '90200000-0000-0000-0000-000000000031'::uuid,
            '90200000-0000-0000-0000-000000000001'::uuid,
            '90200000-0000-0000-0000-000000000041'::uuid,
            '{"answers": [{"question_id": "90200000-0000-0000-0000-000000000101", "value": "90200000-0000-0000-0000-000000000202"}]}'::jsonb
        )
    $$,
    $$ values (true) $$,
    'Should report pending attendance became confirmed after answers are submitted'
);

-- Should store answers and mark the attendee confirmed
select results_eq(
    $$
        select status, registration_answers
        from event_attendee
        where event_id = '90200000-0000-0000-0000-000000000041'::uuid
        and user_id = '90200000-0000-0000-0000-000000000031'::uuid
    $$,
    $$ values ('confirmed'::text, '{"answers": [{"question_id": "90200000-0000-0000-0000-000000000101", "value": "90200000-0000-0000-0000-000000000202"}]}'::jsonb) $$,
    'Should store answers and mark the attendee confirmed'
);

-- Should create the expected audit row
select ok(
    exists(
        select 1
        from audit_log
        where action = 'event_registration_questions_answered'
        and actor_user_id = :'pendingUserID'::uuid
        and event_id = :'eventID'::uuid
    ),
    'Should create the expected audit row'
);

-- Should report ticketed pending attendance stays unconfirmed while checkout is unpaid
select results_eq(
    $$
        select submit_event_registration_answers(
            '90200000-0000-0000-0000-000000000035'::uuid,
            '90200000-0000-0000-0000-000000000001'::uuid,
            '90200000-0000-0000-0000-000000000044'::uuid,
            '{"answers": [{"question_id": "90200000-0000-0000-0000-000000000101", "value": "90200000-0000-0000-0000-000000000202"}]}'::jsonb
        )
    $$,
    $$ values (false) $$,
    'Should report ticketed pending attendance stays unconfirmed while checkout is unpaid'
);

-- Should store ticketed answers but leave pending attendance unconfirmed
select results_eq(
    $$
        select status, registration_answers
        from event_attendee
        where event_id = '90200000-0000-0000-0000-000000000044'::uuid
        and user_id = '90200000-0000-0000-0000-000000000035'::uuid
    $$,
    $$ values ('registration-questions-pending'::text, '{"answers": [{"question_id": "90200000-0000-0000-0000-000000000101", "value": "90200000-0000-0000-0000-000000000202"}]}'::jsonb) $$,
    'Should store ticketed answers but leave pending attendance unconfirmed'
);

-- Should report confirmed attendee answer updates do not become newly confirmed
select results_eq(
    $$
        select submit_event_registration_answers(
            '90200000-0000-0000-0000-000000000032'::uuid,
            '90200000-0000-0000-0000-000000000001'::uuid,
            '90200000-0000-0000-0000-000000000041'::uuid,
            '{"answers": [{"question_id": "90200000-0000-0000-0000-000000000101", "value": "90200000-0000-0000-0000-000000000202"}]}'::jsonb
        )
    $$,
    $$ values (false) $$,
    'Should report confirmed attendee answer updates do not become newly confirmed'
);

-- Should reject confirmed attendee updates after the event starts
select throws_ok(
    $$
        select submit_event_registration_answers(
            '90200000-0000-0000-0000-000000000033'::uuid,
            '90200000-0000-0000-0000-000000000001'::uuid,
            '90200000-0000-0000-0000-000000000042'::uuid,
            '{"answers": [{"question_id": "90200000-0000-0000-0000-000000000101", "value": "Changed"}]}'::jsonb
        )
    $$,
    'registration answers can only be submitted before the event starts',
    'Should reject confirmed attendee updates after the event starts'
);

-- Should reject events without registration questions
select throws_ok(
    $$
        select submit_event_registration_answers(
            '90200000-0000-0000-0000-000000000031'::uuid,
            '90200000-0000-0000-0000-000000000001'::uuid,
            '90200000-0000-0000-0000-000000000043'::uuid,
            '{"answers": []}'::jsonb
        )
    $$,
    'event does not have registration questions',
    'Should reject events without registration questions'
);

-- Should reject invalid answers
select throws_ok(
    $$
        select submit_event_registration_answers(
            '90200000-0000-0000-0000-000000000032'::uuid,
            '90200000-0000-0000-0000-000000000001'::uuid,
            '90200000-0000-0000-0000-000000000041'::uuid,
            '{"answers": []}'::jsonb
        )
    $$,
    'required questionnaire answer is missing',
    'Should reject invalid answers'
);

-- Should reject users without an attendee row
select throws_ok(
    $$
        select submit_event_registration_answers(
            '90200000-0000-0000-0000-000000000034'::uuid,
            '90200000-0000-0000-0000-000000000001'::uuid,
            '90200000-0000-0000-0000-000000000041'::uuid,
            '{"answers": [{"question_id": "90200000-0000-0000-0000-000000000101", "value": "90200000-0000-0000-0000-000000000201"}]}'::jsonb
        )
    $$,
    'event registration not found',
    'Should reject users without an attendee row'
);

-- Should reject events outside the route community
select throws_ok(
    $$
        select submit_event_registration_answers(
            '90200000-0000-0000-0000-000000000032'::uuid,
            '90200000-0000-0000-0000-000000000009'::uuid,
            '90200000-0000-0000-0000-000000000041'::uuid,
            '{"answers": [{"question_id": "90200000-0000-0000-0000-000000000101", "value": "90200000-0000-0000-0000-000000000201"}]}'::jsonb
        )
    $$,
    'event not found or inactive',
    'Should reject events outside the route community'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
