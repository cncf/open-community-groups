-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(16);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '4a150000-0000-0000-0000-000000000001'
\set eventCategoryID '4a150000-0000-0000-0000-000000000002'
\set eventID '4a150000-0000-0000-0000-000000000003'
\set eventNoQuestionsID '4a150000-0000-0000-0000-000000000004'
\set eventRegistrationClosedID '4a150000-0000-0000-0000-000000000021'
\set eventStartedID '4a150000-0000-0000-0000-000000000005'
\set eventTicketedRegistrationClosedID '4a150000-0000-0000-0000-000000000024'
\set eventTicketedID '4a150000-0000-0000-0000-000000000006'
\set eventTicketedRegistrationClosedPriceWindowID '4a150000-0000-0000-0000-000000000027'
\set eventTicketedRegistrationClosedTicketTypeID '4a150000-0000-0000-0000-000000000025'
\set eventTicketTypeID '4a150000-0000-0000-0000-000000000007'
\set groupCategoryID '4a150000-0000-0000-0000-000000000008'
\set groupID '4a150000-0000-0000-0000-000000000009'
\set nonAttendeeUserID '4a150000-0000-0000-0000-000000000010'
\set optionStandardID '4a150000-0000-0000-0000-000000000011'
\set optionVegetarianID '4a150000-0000-0000-0000-000000000012'
\set pendingPurchaseID '4a150000-0000-0000-0000-000000000013'
\set pendingUserID '4a150000-0000-0000-0000-000000000014'
\set priceWindowID '4a150000-0000-0000-0000-000000000015'
\set questionID '4a150000-0000-0000-0000-000000000016'
\set startedEventUserID '4a150000-0000-0000-0000-000000000017'
\set ticketedPendingUserID '4a150000-0000-0000-0000-000000000018'
\set unknownCommunityID '4a150000-0000-0000-0000-000000000019'
\set updateUserID '4a150000-0000-0000-0000-000000000020'
\set windowCheckoutPurchaseID '4a150000-0000-0000-0000-000000000028'
\set windowCheckoutUserID '4a150000-0000-0000-0000-000000000026'
\set windowManualUserID '4a150000-0000-0000-0000-000000000022'
\set windowSelfUserID '4a150000-0000-0000-0000-000000000023'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'communityID',
    'answers-community',
    'Answers Community',
    'Community for testing registration answers',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'General');

-- Users
insert into "user" (
    user_id,
    auth_hash,
    email,
    email_verified,
    username
) values (
    :'pendingUserID',
    'hash-1',
    'pending@example.com',
    true,
    'pending-user'
), (
    :'updateUserID',
    'hash-2',
    'update@example.com',
    true,
    'update-user'
), (
    :'startedEventUserID',
    'hash-3',
    'started-event@example.com',
    true,
    'started-event-user'
), (
    :'nonAttendeeUserID',
    'hash-4',
    'non-attendee@example.com',
    true,
    'non-attendee'
), (
    :'ticketedPendingUserID',
    'hash-5',
    'ticketed-pending@example.com',
    true,
    'ticketed-pending'
), (
    :'windowManualUserID',
    'hash-6',
    'window-manual@example.com',
    true,
    'window-manual'
), (
    :'windowSelfUserID',
    'hash-7',
    'window-self@example.com',
    true,
    'window-self'
), (
    :'windowCheckoutUserID',
    'hash-8',
    'window-checkout@example.com',
    true,
    'window-checkout'
);

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Answers Group', 'answers-group');

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
    registration_questions,
    registration_ends_at
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
    format(
        $json$
            [
                {
                    "id": "%s",
                    "kind": "single-select",
                    "prompt": "Meal",
                    "required": true,
                    "options": [
                        {"id": "%s", "label": "Standard"},
                        {"id": "%s", "label": "Vegetarian"}
                    ]
                }
            ]
        $json$,
        :'questionID',
        :'optionStandardID',
        :'optionVegetarianID'
    )::jsonb,
    null
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
    format(
        $json$
            [
                {
                    "id": "%s",
                    "kind": "free-text",
                    "prompt": "Note",
                    "required": true,
                    "options": []
                }
            ]
        $json$,
        :'questionID'
    )::jsonb,
    null
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
    '[]'::jsonb,
    null
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
    format(
        $json$
            [
                {
                    "id": "%s",
                    "kind": "single-select",
                    "prompt": "Meal",
                    "required": true,
                    "options": [
                        {"id": "%s", "label": "Standard"},
                        {"id": "%s", "label": "Vegetarian"}
                    ]
                }
            ]
        $json$,
        :'questionID',
        :'optionStandardID',
        :'optionVegetarianID'
    )::jsonb,
    null
), (
    :'eventRegistrationClosedID',
    :'groupID',
    'Closed Answers Event',
    'closed-answers-event',
    'Desc',
    'UTC',
    :'eventCategoryID',
    'in-person',
    true,
    now() + interval '7 days',
    null,
    format(
        $json$
            [
                {
                    "id": "%s",
                    "kind": "single-select",
                    "prompt": "Meal",
                    "required": true,
                    "options": [
                        {"id": "%s", "label": "Standard"},
                        {"id": "%s", "label": "Vegetarian"}
                    ]
                }
            ]
        $json$,
        :'questionID',
        :'optionStandardID',
        :'optionVegetarianID'
    )::jsonb,
    current_timestamp - interval '1 hour'
), (
    :'eventTicketedRegistrationClosedID',
    :'groupID',
    'Closed Ticketed Answers Event',
    'closed-ticketed-answers-event',
    'Desc',
    'UTC',
    :'eventCategoryID',
    'in-person',
    true,
    now() + interval '7 days',
    'USD',
    format(
        $json$
            [
                {
                    "id": "%s",
                    "kind": "single-select",
                    "prompt": "Meal",
                    "required": true,
                    "options": [
                        {"id": "%s", "label": "Standard"},
                        {"id": "%s", "label": "Vegetarian"}
                    ]
                }
            ]
        $json$,
        :'questionID',
        :'optionStandardID',
        :'optionVegetarianID'
    )::jsonb,
    current_timestamp - interval '1 hour'
);

-- Event tickets
insert into event_ticket_type (event_ticket_type_id, event_id, "order", seats_total, title)
values
    (:'eventTicketTypeID', :'eventTicketedID', 1, 10, 'General admission'),
    (
        :'eventTicketedRegistrationClosedTicketTypeID',
        :'eventTicketedRegistrationClosedID',
        1,
        10,
        'General admission'
    );

-- Ticket price windows
insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values (
    :'priceWindowID',
    1000,
    :'eventTicketTypeID'
), (
    :'eventTicketedRegistrationClosedPriceWindowID',
    1000,
    :'eventTicketedRegistrationClosedTicketTypeID'
);

-- Event attendees
insert into event_attendee (event_id, user_id, registration_answers, status)
values
    (:'eventID', :'pendingUserID', null, 'registration-questions-pending'),
    (
        :'eventID',
        :'updateUserID',
        format(
            '{"answers": [{"question_id": "%s", "value": "%s"}]}',
            :'questionID',
            :'optionStandardID'
        )::jsonb,
        'confirmed'
    ),
    (
        :'eventStartedID',
        :'startedEventUserID',
        format(
            '{"answers": [{"question_id": "%s", "value": "Initial"}]}',
            :'questionID'
        )::jsonb,
        'confirmed'
    ),
    (:'eventNoQuestionsID', :'pendingUserID', null, 'confirmed'),
    (:'eventTicketedID', :'ticketedPendingUserID', null, 'registration-questions-pending'),
    (
        :'eventTicketedRegistrationClosedID',
        :'windowCheckoutUserID',
        null,
        'registration-questions-pending'
    ),
    (
        :'eventRegistrationClosedID',
        :'windowSelfUserID',
        format(
            '{"answers": [{"question_id": "%s", "value": "%s"}]}',
            :'questionID',
            :'optionStandardID'
        )::jsonb,
        'confirmed'
    );

-- Manually invited attendee allowed through the closed registration window
insert into event_attendee (event_id, user_id, manually_invited, status)
values (
    :'eventRegistrationClosedID',
    :'windowManualUserID',
    true,
    'registration-questions-pending'
);

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
), (
    :'windowCheckoutPurchaseID',
    1000,
    'USD',
    :'eventTicketedRegistrationClosedID',
    :'eventTicketedRegistrationClosedTicketTypeID',
    now() + interval '10 minutes',
    'pending',
    'General admission',
    :'windowCheckoutUserID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should report pending attendance became confirmed after answers are submitted
select results_eq(
    format(
        $$
            select submit_event_registration_answers(
                %L::uuid,
                %L::uuid,
                %L::uuid,
                '{"answers": [{"question_id": "%s", "value": "%s"}]}'::jsonb
            )
        $$,
        :'pendingUserID',
        :'communityID',
        :'eventID',
        :'questionID',
        :'optionVegetarianID'
    ),
    $$ values (true) $$,
    'Should report pending attendance became confirmed after answers are submitted'
);

-- Should store answers and mark the attendee confirmed
select results_eq(
    format(
        $$
            select status, registration_answers
            from event_attendee
            where event_id = %L::uuid
            and user_id = %L::uuid
        $$,
        :'eventID',
        :'pendingUserID'
    ),
    format(
        $$
            values (
                'confirmed'::text,
                '{"answers": [{"question_id": "%s", "value": "%s"}]}'::jsonb
            )
        $$,
        :'questionID',
        :'optionVegetarianID'
    ),
    'Should store answers and mark the attendee confirmed'
);

-- Should create the expected audit row
select results_eq(
    format(
        $$
        select
            action,
            actor_user_id,
            community_id,
            details,
            event_id,
            group_id,
            resource_id,
            resource_type
        from audit_log
        where action = 'event_registration_questions_answered'
        and resource_id = %L::uuid
        $$,
        :'pendingUserID'
    ),
    format(
        $$
        values (
            'event_registration_questions_answered',
            %L::uuid,
            %L::uuid,
            '{"event_id": "%s", "user_id": "%s"}'::jsonb,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            'user'
        )
        $$,
        :'pendingUserID', :'communityID', :'eventID', :'pendingUserID', :'eventID', :'groupID', :'pendingUserID'
    ),
    'Should create the expected audit row'
);

-- Should report ticketed pending attendance stays unconfirmed while checkout is unpaid
select results_eq(
    format(
        $$
            select submit_event_registration_answers(
                %L::uuid,
                %L::uuid,
                %L::uuid,
                '{"answers": [{"question_id": "%s", "value": "%s"}]}'::jsonb
            )
        $$,
        :'ticketedPendingUserID',
        :'communityID',
        :'eventTicketedID',
        :'questionID',
        :'optionVegetarianID'
    ),
    $$ values (false) $$,
    'Should report ticketed pending attendance stays unconfirmed while checkout is unpaid'
);

-- Should store ticketed answers but leave pending attendance unconfirmed
select results_eq(
    format(
        $$
            select status, registration_answers
            from event_attendee
            where event_id = %L::uuid
            and user_id = %L::uuid
        $$,
        :'eventTicketedID',
        :'ticketedPendingUserID'
    ),
    format(
        $$
            values (
                'registration-questions-pending'::text,
                '{"answers": [{"question_id": "%s", "value": "%s"}]}'::jsonb
            )
        $$,
        :'questionID',
        :'optionVegetarianID'
    ),
    'Should store ticketed answers but leave pending attendance unconfirmed'
);

-- Should reject self-service answer updates after the registration window closes
select throws_ok(
    format(
        $$
            select submit_event_registration_answers(
                %L::uuid,
                %L::uuid,
                %L::uuid,
                '{"answers": [{"question_id": "%s", "value": "%s"}]}'::jsonb
            )
        $$,
        :'windowSelfUserID',
        :'communityID',
        :'eventRegistrationClosedID',
        :'questionID',
        :'optionVegetarianID'
    ),
    'event registration is not open',
    'Should reject registration answer updates after the registration window closes'
);

-- Should allow active checkout holds to answer after the registration window closes
select results_eq(
    format(
        $$
            select submit_event_registration_answers(
                %L::uuid,
                %L::uuid,
                %L::uuid,
                '{"answers": [{"question_id": "%s", "value": "%s"}]}'::jsonb
            )
        $$,
        :'windowCheckoutUserID',
        :'communityID',
        :'eventTicketedRegistrationClosedID',
        :'questionID',
        :'optionVegetarianID'
    ),
    $$ values (false) $$,
    'Should allow active checkout holds to answer after the registration window closes'
);

-- Should store active checkout hold answers after the registration window closes
select results_eq(
    format(
        $$
            select status, registration_answers
            from event_attendee
            where event_id = %L::uuid
            and user_id = %L::uuid
        $$,
        :'eventTicketedRegistrationClosedID',
        :'windowCheckoutUserID'
    ),
    format(
        $$
            values (
                'registration-questions-pending'::text,
                '{"answers": [{"question_id": "%s", "value": "%s"}]}'::jsonb
            )
        $$,
        :'questionID',
        :'optionVegetarianID'
    ),
    'Should store active checkout hold answers after the registration window closes'
);

-- Should allow manually invited users to answer after the registration window closes
select results_eq(
    format(
        $$
            select submit_event_registration_answers(
                %L::uuid,
                %L::uuid,
                %L::uuid,
                '{"answers": [{"question_id": "%s", "value": "%s"}]}'::jsonb
            )
        $$,
        :'windowManualUserID',
        :'communityID',
        :'eventRegistrationClosedID',
        :'questionID',
        :'optionVegetarianID'
    ),
    $$ values (true) $$,
    'Should allow manually invited users to answer after the registration window closes'
);

-- Should report confirmed attendee answer updates do not become newly confirmed
select results_eq(
    format(
        $$
            select submit_event_registration_answers(
                %L::uuid,
                %L::uuid,
                %L::uuid,
                '{"answers": [{"question_id": "%s", "value": "%s"}]}'::jsonb
            )
        $$,
        :'updateUserID',
        :'communityID',
        :'eventID',
        :'questionID',
        :'optionVegetarianID'
    ),
    $$ values (false) $$,
    'Should report confirmed attendee answer updates do not become newly confirmed'
);

-- Should reject confirmed attendee updates after the event starts
select throws_ok(
    format(
        $$
            select submit_event_registration_answers(
                %L::uuid,
                %L::uuid,
                %L::uuid,
                '{"answers": [{"question_id": "%s", "value": "Changed"}]}'::jsonb
            )
        $$,
        :'startedEventUserID',
        :'communityID',
        :'eventStartedID',
        :'questionID'
    ),
    'registration answers can only be submitted before the event starts',
    'Should reject confirmed attendee updates after the event starts'
);

-- Should reject started events before validating answers
select throws_ok(
    format(
        $$
            select submit_event_registration_answers(
                %L::uuid,
                %L::uuid,
                %L::uuid,
                '{"answers": []}'::jsonb
            )
        $$,
        :'startedEventUserID',
        :'communityID',
        :'eventStartedID'
    ),
    'registration answers can only be submitted before the event starts',
    'Should reject started events before validating answers'
);

-- Should reject events without registration questions
select throws_ok(
    format(
        $$
            select submit_event_registration_answers(
                %L::uuid,
                %L::uuid,
                %L::uuid,
                '{"answers": []}'::jsonb
            )
        $$,
        :'pendingUserID',
        :'communityID',
        :'eventNoQuestionsID'
    ),
    'event does not have registration questions',
    'Should reject events without registration questions'
);

-- Should reject invalid answers
select throws_ok(
    format(
        $$
            select submit_event_registration_answers(
                %L::uuid,
                %L::uuid,
                %L::uuid,
                '{"answers": []}'::jsonb
            )
        $$,
        :'updateUserID',
        :'communityID',
        :'eventID'
    ),
    'required questionnaire answer is missing',
    'Should reject invalid answers'
);

-- Should reject users without an attendee row
select throws_ok(
    format(
        $$
            select submit_event_registration_answers(
                %L::uuid,
                %L::uuid,
                %L::uuid,
                '{"answers": [{"question_id": "%s", "value": "%s"}]}'::jsonb
            )
        $$,
        :'nonAttendeeUserID',
        :'communityID',
        :'eventID',
        :'questionID',
        :'optionStandardID'
    ),
    'event registration not found',
    'Should reject users without an attendee row'
);

-- Should reject events outside the route community
select throws_ok(
    format(
        $$
            select submit_event_registration_answers(
                %L::uuid,
                %L::uuid,
                %L::uuid,
                '{"answers": [{"question_id": "%s", "value": "%s"}]}'::jsonb
            )
        $$,
        :'updateUserID',
        :'unknownCommunityID',
        :'eventID',
        :'questionID',
        :'optionStandardID'
    ),
    'event not found or inactive',
    'Should reject events outside the route community'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
