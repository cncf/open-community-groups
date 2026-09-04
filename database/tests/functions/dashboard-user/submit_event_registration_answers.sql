-- Tests submitting attendee registration answers.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(16);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '4a070000-0000-0000-0000-000000000001'
\set eventCategoryID '4a070000-0000-0000-0000-000000000002'
\set eventID '4a070000-0000-0000-0000-000000000003'
\set eventNoQuestionsID '4a070000-0000-0000-0000-000000000004'
\set eventRegistrationClosedID '4a070000-0000-0000-0000-000000000021'
\set eventStartedID '4a070000-0000-0000-0000-000000000005'
\set eventTicketedRegistrationClosedID '4a070000-0000-0000-0000-000000000024'
\set eventTicketedID '4a070000-0000-0000-0000-000000000006'
\set eventTicketedRegistrationClosedPriceWindowID '4a070000-0000-0000-0000-000000000027'
\set eventTicketedRegistrationClosedTicketTypeID '4a070000-0000-0000-0000-000000000025'
\set eventTicketTypeID '4a070000-0000-0000-0000-000000000007'
\set groupCategoryID '4a070000-0000-0000-0000-000000000008'
\set groupID '4a070000-0000-0000-0000-000000000009'
\set nonAttendeeUserID '4a070000-0000-0000-0000-000000000010'
\set optionStandardID '4a070000-0000-0000-0000-000000000011'
\set optionVegetarianID '4a070000-0000-0000-0000-000000000012'
\set pendingPurchaseID '4a070000-0000-0000-0000-000000000013'
\set pendingUserID '4a070000-0000-0000-0000-000000000014'
\set priceWindowID '4a070000-0000-0000-0000-000000000015'
\set questionID '4a070000-0000-0000-0000-000000000016'
\set startedEventUserID '4a070000-0000-0000-0000-000000000017'
\set ticketedPendingUserID '4a070000-0000-0000-0000-000000000018'
\set unknownCommunityID '4a070000-0000-0000-0000-000000000019'
\set updateUserID '4a070000-0000-0000-0000-000000000020'
\set windowCheckoutPurchaseID '4a070000-0000-0000-0000-000000000028'
\set windowCheckoutUserID '4a070000-0000-0000-0000-000000000026'
\set windowManualUserID '4a070000-0000-0000-0000-000000000022'
\set windowSelfUserID '4a070000-0000-0000-0000-000000000023'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, group categories, event categories, users and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'pendingUserID');
select fx_user(:'updateUserID');
select fx_user(:'startedEventUserID');
select fx_user(:'nonAttendeeUserID');
select fx_user(:'ticketedPendingUserID');
select fx_user(:'windowManualUserID');
select fx_user(:'windowSelfUserID');
select fx_user(:'windowCheckoutUserID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Events
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'registration_questions', format(
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
    'starts_at', now() + interval '1 day'
));
select fx_event(:'eventStartedID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'registration_questions', format(
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
    'starts_at', now() - interval '1 hour'
));
select fx_event(:'eventNoQuestionsID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', now() + interval '7 days'
));
select fx_event(:'eventTicketedID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD',
    'published', true,
    'registration_questions', format(
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
    'starts_at', now() + interval '2 days'
));
select fx_event(:'eventRegistrationClosedID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'registration_ends_at', current_timestamp - interval '1 hour',
    'registration_questions', format(
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
    'starts_at', now() + interval '7 days'
));
select fx_event(:'eventTicketedRegistrationClosedID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD',
    'published', true,
    'registration_ends_at', current_timestamp - interval '1 hour',
    'registration_questions', format(
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
    'starts_at', now() + interval '7 days'
));

-- Event tickets
select fx_event_ticket_type(:'eventTicketTypeID', :'eventTicketedID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General admission'
));
select fx_event_ticket_type(:'eventTicketedRegistrationClosedTicketTypeID', :'eventTicketedRegistrationClosedID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General admission'
));

-- Ticket price windows
select fx_event_ticket_price_window(:'priceWindowID', :'eventTicketTypeID', jsonb_build_object('amount_minor', 1000));
select fx_event_ticket_price_window(:'eventTicketedRegistrationClosedPriceWindowID', :'eventTicketedRegistrationClosedTicketTypeID', jsonb_build_object('amount_minor', 1000));

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
    0,
    'USD',
    :'eventTicketedID',
    :'eventTicketTypeID',
    now() + interval '10 minutes',
    'pending',
    'General admission',
    :'ticketedPendingUserID'
), (
    :'windowCheckoutPurchaseID',
    0,
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

-- Should store answers while checkout retains pending confirmation
select lives_ok(
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
    'Should accept answers for a pending registration'
);

-- Should store answers without confirming the attendee
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
                'registration-questions-pending'::text,
                '{"answers": [{"question_id": "%s", "value": "%s"}]}'::jsonb
            )
        $$,
        :'questionID',
        :'optionVegetarianID'
    ),
    'Should store answers while leaving confirmation to checkout'
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

-- Should keep pending checkout attendance unconfirmed while checkout is unpaid
select lives_ok(
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
    'Should accept answers while checkout is unpaid'
);

-- Should store checkout answers but leave pending attendance unconfirmed
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
    'Should store checkout answers but leave pending attendance unconfirmed'
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
    'OCG01',
    'event registration is not open',
    'Should reject registration answer updates after the registration window closes'
);

-- Should allow active checkout holds to answer after the registration window closes
select lives_ok(
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
select lives_ok(
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
    'Should allow manually invited users to answer after the registration window closes'
);

-- Should update a confirmed attendee's answers without changing enrollment
select lives_ok(
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
    'Should update confirmed attendee answers'
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
    'OCG01',
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
    'OCG01',
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
    'OCG01',
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
    'OCG01',
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
    'OCG01',
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
    'OCG01',
    'event not found or inactive',
    'Should reject events outside the route community'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
