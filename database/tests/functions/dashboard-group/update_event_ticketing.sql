-- Tests updating event ticketing configuration.
-- Split from update_event.sql to keep that file a manageable size.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(37);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set category1ID '3a3c0000-0000-0000-0000-000000000001'
\set community1ID '3a3c0000-0000-0000-0000-000000000002'
\set datedDiscountCodeID '3a3c0000-0000-0000-0000-00000000006b'
\set datedEventID '3a3c0000-0000-0000-0000-00000000006c'
\set datedPriceWindowID '3a3c0000-0000-0000-0000-00000000006d'
\set datedTicketTypeID '3a3c0000-0000-0000-0000-00000000006e'
\set event19DiscountCodeID '3a3c0000-0000-0000-0000-000000000035'
\set event19ID '3a3c0000-0000-0000-0000-000000000008'
\set event19PriceWindowID '3a3c0000-0000-0000-0000-000000000034'
\set event19TicketTypeID '3a3c0000-0000-0000-0000-000000000033'
\set event22ID '3a3c0000-0000-0000-0000-000000000011'
\set event22MissingCurrencyPriceWindowID '3a3c0000-0000-0000-0000-000000000048'
\set event22MissingCurrencyTicketTypeID '3a3c0000-0000-0000-0000-000000000047'
\set event22PriceWindowID '3a3c0000-0000-0000-0000-00000000006f'
\set event22TicketTypeID '3a3c0000-0000-0000-0000-000000000070'
\set event22WaitlistPriceWindowID '3a3c0000-0000-0000-0000-000000000050'
\set event22WaitlistTicketTypeID '3a3c0000-0000-0000-0000-000000000049'
\set event23ID '3a3c0000-0000-0000-0000-000000000012'
\set event23PriceWindowID '3a3c0000-0000-0000-0000-000000000071'
\set event23TicketTypeID '3a3c0000-0000-0000-0000-000000000072'
\set event24ID '3a3c0000-0000-0000-0000-000000000013'
\set event24PriceWindowID '3a3c0000-0000-0000-0000-000000000073'
\set event24TicketTypeID '3a3c0000-0000-0000-0000-000000000074'
\set eventPaidTransitionID '3a3c0000-0000-0000-0000-000000000068'
\set eventQuestionsAnsweredID '3a3c0000-0000-0000-0000-000000000015'
\set eventQuestionsAnsweredPriceWindowID '3a3c0000-0000-0000-0000-000000000075'
\set eventQuestionsAnsweredTicketTypeID '3a3c0000-0000-0000-0000-000000000076'
\set eventQuestionsHoldID '3a3c0000-0000-0000-0000-000000000056'
\set eventQuestionsID '3a3c0000-0000-0000-0000-000000000016'
\set eventQuestionsPriceWindowID '3a3c0000-0000-0000-0000-000000000077'
\set eventQuestionsPublishedID '3a3c0000-0000-0000-0000-000000000017'
\set eventQuestionsPublishedPriceWindowID '3a3c0000-0000-0000-0000-000000000078'
\set eventQuestionsPublishedTicketTypeID '3a3c0000-0000-0000-0000-000000000079'
\set eventQuestionsTicketTypeID '3a3c0000-0000-0000-0000-00000000007a'
\set eventTicketQueueID '3a3c0000-0000-0000-0000-000000000064'
\set group1ID '3a3c0000-0000-0000-0000-000000000018'
\set groupCategoryID '3a3c0000-0000-0000-0000-000000000030'
\set otherDiscountCodeID '3a3c0000-0000-0000-0000-000000000043'
\set otherEventID '3a3c0000-0000-0000-0000-000000000032'
\set otherPriceWindowID '3a3c0000-0000-0000-0000-00000000007b'
\set otherTicketTypeID '3a3c0000-0000-0000-0000-000000000041'
\set paidTransitionPriceWindowID '3a3c0000-0000-0000-0000-00000000006a'
\set paidTransitionTicketTypeID '3a3c0000-0000-0000-0000-000000000069'
\set questionsAttendeeUserID '3a3c0000-0000-0000-0000-000000000019'
\set questionsCategoryID '3a3c0000-0000-0000-0000-000000000020'
\set questionsCommunityID '3a3c0000-0000-0000-0000-000000000021'
\set questionsEventCategoryID '3a3c0000-0000-0000-0000-000000000022'
\set questionsGroupID '3a3c0000-0000-0000-0000-000000000023'
\set questionsHoldPriceWindowID '3a3c0000-0000-0000-0000-000000000060'
\set questionsHoldPurchaseID '3a3c0000-0000-0000-0000-000000000059'
\set questionsHoldTicketTypeID '3a3c0000-0000-0000-0000-000000000058'
\set questionsHoldUserID '3a3c0000-0000-0000-0000-000000000057'
\set questionsOrganizerUserID '3a3c0000-0000-0000-0000-000000000024'
\set registrationQuestionID '3a3c0000-0000-0000-0000-000000000031'
\set ticketQueuePriceWindowID '3a3c0000-0000-0000-0000-000000000065'
\set ticketQueuePurchaseID '3a3c0000-0000-0000-0000-000000000066'
\set ticketQueueTicketTypeID '3a3c0000-0000-0000-0000-000000000067'
\set unseededPriceWindowID '3a3c0000-0000-0000-0000-000000000044'
\set user1ID '3a3c0000-0000-0000-0000-000000000025'
\set user4ID '3a3c0000-0000-0000-0000-000000000028'
\set user5ID '3a3c0000-0000-0000-0000-000000000029'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories, event categories and users
select fx_community(:'community1ID');
select fx_community(:'questionsCommunityID');
select fx_group_category(:'groupCategoryID', :'community1ID');
select fx_group_category(:'questionsCategoryID', :'questionsCommunityID');
select fx_event_category(:'category1ID', :'community1ID');
select fx_event_category(:'questionsEventCategoryID', :'questionsCommunityID');
select fx_user(:'user1ID');
select fx_user(:'user4ID');
select fx_user(:'user5ID');
select fx_user(:'questionsOrganizerUserID');
select fx_user(:'questionsAttendeeUserID');
select fx_user(:'questionsHoldUserID');

-- Group
select fx_group(:'group1ID', :'community1ID', :'groupCategoryID', jsonb_build_object('payment_recipient', '{"provider": "stripe", "recipient_id": "acct_update_ticketing", "seller_display_name": "Update Ticketing Fiscal Sponsor"}'::jsonb));

-- Group for registration-question update tests
select fx_group(:'questionsGroupID', :'questionsCommunityID', :'questionsCategoryID', jsonb_build_object('payment_recipient', '{"provider": "stripe", "recipient_id": "acct_update_questions", "seller_display_name": "Questions Fiscal Sponsor"}'::jsonb));

-- Events used to update and lock registration questions
select fx_event(:'eventQuestionsID', :'questionsGroupID', :'questionsEventCategoryID', jsonb_build_object(
    'description', 'Desc',
    'name', 'Draft Questions Event',
    'starts_at', '2030-01-01 10:00:00+00'
));
select fx_event(:'eventQuestionsPublishedID', :'questionsGroupID', :'questionsEventCategoryID', jsonb_build_object(
    'description', 'Desc',
    'name', 'Published Questions Event',
    'published', true,
    'registration_questions', jsonb_build_array(jsonb_build_object(
        'id', :'registrationQuestionID',
        'kind', 'free-text',
        'options', '[]'::jsonb,
        'prompt', 'Original',
        'required', true
    )),
    'starts_at', '2030-01-01 10:00:00+00'
));
select fx_event(:'eventQuestionsAnsweredID', :'questionsGroupID', :'questionsEventCategoryID', jsonb_build_object(
    'description', 'Desc',
    'name', 'Answered Questions Event',
    'registration_questions', jsonb_build_array(jsonb_build_object(
        'id', :'registrationQuestionID',
        'kind', 'free-text',
        'options', '[]'::jsonb,
        'prompt', 'Original',
        'required', true
    )),
    'starts_at', '2030-01-01 10:00:00+00'
));
select fx_event(:'eventQuestionsHoldID', :'questionsGroupID', :'questionsEventCategoryID', jsonb_build_object(
    'description', 'Desc',
    'name', 'Held Questions Event',
    'payment_currency_code', 'USD',
    'published', true,
    'registration_questions', jsonb_build_array(jsonb_build_object(
        'id', :'registrationQuestionID',
        'kind', 'free-text',
        'options', '[]'::jsonb,
        'prompt', 'Original',
        'required', true
    )),
    'starts_at', '2030-01-01 10:00:00+00'
));

-- Event used for admission-tier payload validation checks
select fx_event(:'event22ID', :'group1ID', :'category1ID', jsonb_build_object(
    'description', 'Event used for admission-tier payload validation checks',
    'event_kind_id', 'virtual',
    'name', 'Admission Payload Event'
));

-- Published event used for ticketing conversion waitlist checks
select fx_event(:'event23ID', :'group1ID', :'category1ID', jsonb_build_object(
    'description', 'Published event used for ticketing conversion waitlist checks',
    'ends_at', '2030-05-01 12:00:00+00',
    'name', 'Ticketing Waitlist Event',
    'published', true,
    'starts_at', '2030-05-01 10:00:00+00',
    'waitlist_enabled', true
));

-- Approval-required event used for invitation request transition checks
select fx_event(:'event24ID', :'group1ID', :'category1ID', jsonb_build_object(
    'attendee_approval_required', true,
    'description', 'Approval-required event used for invitation request checks',
    'event_kind_id', 'virtual',
    'name', 'Approval Request Event'
));

-- Paid event used for ticketing preservation checks
select fx_event(:'event19ID', :'group1ID', :'category1ID', jsonb_build_object(
    'description', 'Event seeded for ticketing preservation tests',
    'name', 'Paid Event',
    'payment_currency_code', 'USD',
    'venue_address', '123 Main St',
    'venue_city', 'San Francisco',
    'venue_country_code', 'US',
    'venue_country_name', 'United States',
    'venue_name', 'Community Hall',
    'venue_state_code', 'CA',
    'venue_state_name', 'California',
    'venue_zip_code', '94105'
));

-- Separate event used only for ticketing ownership checks
select fx_event(:'otherEventID', :'group1ID', :'category1ID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'payment_currency_code', 'USD'
));

-- Paid in-person event without tax whose tier and discount code carry dated windows
select fx_event(:'datedEventID', :'group1ID', :'category1ID', jsonb_build_object(
    'description', 'Dated event used for unrelated edit checks',
    'name', 'Dated Paid Event',
    'payment_currency_code', 'USD',
    'tax_behavior', 'inclusive',
    'tax_calculation_mode', 'none',
    'venue_address', '123 Main St',
    'venue_city', 'San Francisco',
    'venue_country_code', 'US',
    'venue_country_name', 'United States',
    'venue_name', 'Community Hall',
    'venue_state_code', 'CA',
    'venue_state_name', 'California',
    'venue_zip_code', '94105'
));

-- Paid in-person event used for event-kind transition checks
select fx_event(:'eventPaidTransitionID', :'group1ID', :'category1ID', jsonb_build_object(
    'payment_currency_code', 'USD',
    'venue_address', '123 Main St',
    'venue_city', 'San Francisco',
    'venue_country_code', 'US',
    'venue_country_name', 'United States',
    'venue_name', 'Community Hall',
    'venue_state_code', 'CA',
    'venue_state_name', 'California',
    'venue_zip_code', '94105'
));

-- Published ticketed event used to verify tier capacity reconciliation
select fx_event(:'eventTicketQueueID', :'group1ID', :'category1ID', jsonb_build_object(
    'description', 'Published event for ticket queue capacity checks',
    'event_kind_id', 'virtual',
    'name', 'Ticket Queue Capacity Event',
    'payment_currency_code', 'USD',
    'published', true,
    'published_at', current_timestamp,
    'starts_at', current_timestamp + interval '1 day',
    'waitlist_enabled', true
));

-- Paid tier used for event-kind transition checks
select fx_event_ticket_type(:'paidTransitionTicketTypeID', :'eventPaidTransitionID', jsonb_build_object(
    'seats_total', 10
));

-- Event Ticket Price Window
select fx_event_ticket_price_window(:'paidTransitionPriceWindowID', :'paidTransitionTicketTypeID', jsonb_build_object('amount_minor', 2500));

-- Ticket type initially owned by the primary ticketed event
select fx_event_ticket_type(:'event19TicketTypeID', :'event19ID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General'
));

-- Price window for the primary event ticket type
select fx_event_ticket_price_window(:'event19PriceWindowID', :'event19TicketTypeID', jsonb_build_object('amount_minor', 2500));

-- Discount code initially owned by the primary ticketed event
insert into event_discount_code (
    event_discount_code_id,
    active,
    amount_minor,
    code,
    event_id,
    kind,
    title
) values (
    :'event19DiscountCodeID',
    true,
    500,
    'SAVE20',
    :'event19ID',
    'fixed_amount',
    'Launch'
);

-- Dated tier of the dated paid event
select fx_event_ticket_type(:'datedTicketTypeID', :'datedEventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General'
));

-- Bounded dated price window of the dated tier
select fx_event_ticket_price_window(:'datedPriceWindowID', :'datedTicketTypeID', jsonb_build_object(
    'amount_minor', 2500,
    'ends_at', '2030-06-01 10:00:00+00',
    'starts_at', '2030-01-01 10:00:00+00'
));

-- Override-on dated discount code of the dated paid event with live inventory
insert into event_discount_code (
    event_discount_code_id,
    active,
    code,
    event_id,
    kind,
    title,
    available,
    available_override_active,
    ends_at,
    percentage,
    starts_at,
    total_available
) values (
    :'datedDiscountCodeID',
    true,
    'DATED10',
    :'datedEventID',
    'percentage',
    'Dated',
    4,
    true,
    '2030-06-01 10:00:00+00',
    10,
    '2030-01-01 10:00:00+00',
    10
);

-- Ticketing rows on a different event used for ownership checks
select fx_event_ticket_type(:'otherTicketTypeID', :'otherEventID', jsonb_build_object(
    'seats_total', 25
));

-- Full public tier expanded by the capacity reconciliation test
select fx_event_ticket_type(:'ticketQueueTicketTypeID', :'eventTicketQueueID', jsonb_build_object(
    'seats_total', 1,
    'title', 'Queue General'
));

-- Current price for the capacity reconciliation tier
select fx_event_ticket_price_window(:'ticketQueuePriceWindowID', :'ticketQueueTicketTypeID', jsonb_build_object('amount_minor', 2500));

-- Discount code owned by the other event
insert into event_discount_code (
    event_discount_code_id,
    active,
    amount_minor,
    code,
    event_id,
    kind,
    title
) values (
    :'otherDiscountCodeID',
    true,
    250,
    'OTHER25',
    :'otherEventID',
    'fixed_amount',
    'Other launch'
);

-- Ticket type referenced by a pending registration-answer hold
select fx_event_ticket_type(:'questionsHoldTicketTypeID', :'eventQuestionsHoldID', jsonb_build_object(
    'seats_total', 10,
    'title', 'Held General'
));

-- Price window for the held ticket type
select fx_event_ticket_price_window(:'questionsHoldPriceWindowID', :'questionsHoldTicketTypeID', jsonb_build_object('amount_minor', 2500));

-- Completed purchase occupying the capacity reconciliation tier
insert into event_purchase (
    amount_minor,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id
) values (
    0,
    'USD',
    :'eventTicketQueueID',
    :'ticketQueuePurchaseID',
    :'ticketQueueTicketTypeID',
    'completed',
    'Queue General',
    :'user1ID'
);

-- Pending purchase that retains registration answers during ticketing updates
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
    :'questionsHoldPurchaseID',
    0,
    'USD',
    :'eventQuestionsHoldID',
    :'questionsHoldTicketTypeID',
    current_timestamp + interval '10 minutes',
    'pending',
    'Held General',
    :'questionsHoldUserID'
);

-- Single-seat tier for the ticketing conversion waitlist event
select fx_event_ticket_type(:'event23TicketTypeID', :'event23ID', jsonb_build_object('seats_total', 1));

-- Free tiers for events whose ticket inventory is not under test
select fx_event_ticket_type(:'event22TicketTypeID', :'event22ID');
select fx_event_ticket_type(:'event24TicketTypeID', :'event24ID');
select fx_event_ticket_type(:'eventQuestionsAnsweredTicketTypeID', :'eventQuestionsAnsweredID');
select fx_event_ticket_type(:'eventQuestionsPublishedTicketTypeID', :'eventQuestionsPublishedID');
select fx_event_ticket_type(:'eventQuestionsTicketTypeID', :'eventQuestionsID');

-- Current free prices for the free tiers and the other event's tier
select fx_event_ticket_price_window(:'event22PriceWindowID', :'event22TicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'event23PriceWindowID', :'event23TicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'event24PriceWindowID', :'event24TicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'eventQuestionsAnsweredPriceWindowID', :'eventQuestionsAnsweredTicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'eventQuestionsPriceWindowID', :'eventQuestionsTicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'eventQuestionsPublishedPriceWindowID', :'eventQuestionsPublishedTicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'otherPriceWindowID', :'otherTicketTypeID', jsonb_build_object('amount_minor', 0));

-- Attendee with answers that lock registration questions
insert into event_attendee (event_id, user_id, registration_answers, status)
values (
    :'eventQuestionsAnsweredID',
    :'questionsAttendeeUserID',
    jsonb_build_object(
        'answers',
        jsonb_build_array(jsonb_build_object(
            'question_id', :'registrationQuestionID',
            'value', 'Answer'
        ))
    ),
    'confirmed'
);

-- Waitlist entry that blocks enabling attendee approval
insert into event_waitlist (event_id, event_ticket_type_id, user_id)
values (:'event23ID', :'event23TicketTypeID', :'user5ID');

-- Tier-specific FIFO queue promoted after ticket capacity increases
insert into event_waitlist (
    created_at,
    event_id,
    event_ticket_type_id,
    user_id
) values (
    current_timestamp,
    :'eventTicketQueueID',
    :'ticketQueueTicketTypeID',
    :'user4ID'
);

-- Pending invitation request that blocks disabling attendee approval
insert into event_invitation_request (event_id, event_ticket_type_id, user_id)
values (:'event24ID', :'event24TicketTypeID', :'user5ID');

-- Test-only overloads keep existing calls focused while supplying server payment configuration.
create function update_event_with_payments(uuid, uuid, uuid, jsonb)
returns void as $$
    select update_event(
        $1,
        $2,
        $3,
        case
            when $4 ? '_payment_validation' then $4
            else $4 || jsonb_build_object(
                '_payment_validation',
                jsonb_build_object(
                    'expected_payment_recipient', g.payment_recipient,
                    'require_automatic_tax', true,
                    'validated_payment_recipient', g.payment_recipient
                )
            )
        end,
        null,
        'stripe'
    )
    from "group" g
    where g.group_id = $2;
$$ language sql;

create function update_event_with_payments(uuid, uuid, uuid, jsonb, jsonb)
returns void as $$
    select update_event(
        $1,
        $2,
        $3,
        case
            when $4 ? '_payment_validation' then $4
            else $4 || jsonb_build_object(
                '_payment_validation',
                jsonb_build_object(
                    'expected_payment_recipient', g.payment_recipient,
                    'require_automatic_tax', true,
                    'validated_payment_recipient', g.payment_recipient
                )
            )
        end,
        $5,
        'stripe'
    )
    from "group" g
    where g.group_id = $2;
$$ language sql;

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should preserve ticketing fields when payload omits payment controls
select lives_ok(
    format(
        $$select update_event_with_payments(null::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'group1ID',
        :'event19ID',
        jsonb_build_object(
            'category_id', :'category1ID',
            'description', 'Event seeded for ticketing preservation tests',
            'kind_id', 'in-person',
            'meeting_requested', false,
            'name', 'Paid Event Updated',
            'timezone', 'UTC',
            'venue_address', '123 Main St',
            'venue_city', 'San Francisco',
            'venue_country_code', 'US',
            'venue_name', 'Community Hall',
            'venue_state_code', 'CA',
            'venue_state_name', 'California',
            'venue_zip_code', '94105'
        )
    ),
    'Should preserve ticketing fields when payload omits payment controls'
);
select is(
    (
        select jsonb_build_object(
            'discount_codes', list_event_discount_codes(event_id),
            'payment_currency_code', payment_currency_code,
            'ticket_types', list_event_ticket_types(event_id)
        )
        from event
        where event_id = :'event19ID'::uuid
    ),
    jsonb_build_object(
        'discount_codes', jsonb_build_array(
            jsonb_build_object(
                'active', true,
                'amount_minor', 500,
                'available_override_active', false,
                'code', 'SAVE20',
                'event_discount_code_id', :'event19DiscountCodeID',
                'kind', 'fixed_amount',
                'title', 'Launch'
            )
        ),
        'payment_currency_code', 'USD',
        'ticket_types', jsonb_build_array(
            jsonb_build_object(
                'active', true,
                'availability', 'public',
                'current_price', jsonb_build_object(
                    'amount_minor', 2500
                ),
                'event_ticket_type_id', :'event19TicketTypeID',
                'order', 1,
                'price_windows', jsonb_build_array(
                    jsonb_build_object(
                        'amount_minor', 2500,
                        'event_ticket_price_window_id', :'event19PriceWindowID'
                    )
                ),
                'remaining_seats', 10,
                'seats_total', 10,
                'sold_out', false,
                'title', 'General'
            )
        )
    ),
    'Should keep ticketing fields when payload omits payment controls'
);
select is(
    (select capacity from event where event_id = :'event19ID'::uuid),
    10,
    'Should preserve derived capacity when payload omits payment controls'
);

-- Should allow an in-person paid event to become hybrid
select lives_ok(
    format(
        $$select update_event_with_payments(null::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'group1ID',
        :'eventPaidTransitionID',
        jsonb_build_object(
            '_payment_validation', jsonb_build_object(
                'expected_payment_recipient', jsonb_build_object(
                    'provider', 'stripe',
                    'recipient_id', 'acct_update_ticketing',
                    'seller_display_name', 'Update Ticketing Fiscal Sponsor'
                ),
                'require_automatic_tax', true,
                'validated_payment_recipient', jsonb_build_object(
                    'provider', 'stripe',
                    'recipient_id', 'acct_update_ticketing',
                    'seller_display_name', 'Update Ticketing Fiscal Sponsor'
                )
            ),
            'category_id', :'category1ID',
            'description', 'Event seeded for ticketing preservation tests',
            'kind_id', 'hybrid',
            'meeting_requested', false,
            'name', 'Paid Hybrid Event',
            'timezone', 'UTC',
            'venue_address', '123 Main St',
            'venue_city', 'San Francisco',
            'venue_country_code', 'US',
            'venue_country_name', 'United States',
            'venue_name', 'Community Hall',
            'venue_state_code', 'CA',
            'venue_state_name', 'California',
            'venue_zip_code', '94105'
        )
    ),
    'Should allow an in-person paid event to become hybrid'
);

select is(
    (
        select jsonb_build_object(
            'amount_minor', etpw.amount_minor,
            'event_kind_id', e.event_kind_id,
            'payment_currency_code', e.payment_currency_code,
            'venue_address', e.venue_address,
            'venue_city', e.venue_city,
            'venue_country_code', e.venue_country_code,
            'venue_country_name', e.venue_country_name,
            'venue_name', e.venue_name,
            'venue_state_code', e.venue_state_code,
            'venue_state_name', e.venue_state_name,
            'venue_zip_code', e.venue_zip_code
        )
        from event e
        join event_ticket_type ett using (event_id)
        join event_ticket_price_window etpw using (event_ticket_type_id)
        where e.event_id = :'eventPaidTransitionID'::uuid
    ),
    '{
        "amount_minor": 2500,
        "event_kind_id": "hybrid",
        "payment_currency_code": "USD",
        "venue_address": "123 Main St",
        "venue_city": "San Francisco",
        "venue_country_code": "US",
        "venue_country_name": "United States",
        "venue_name": "Community Hall",
        "venue_state_code": "CA",
        "venue_state_name": "California",
        "venue_zip_code": "94105"
    }'::jsonb,
    'Should persist paid hybrid ticketing and its complete physical venue'
);

-- Should reject changing a paid hybrid event to virtual
select throws_ok(
    format(
        $$select update_event_with_payments(null::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'group1ID',
        :'eventPaidTransitionID',
        jsonb_build_object(
            '_payment_validation', jsonb_build_object(
                'expected_payment_recipient', jsonb_build_object(
                    'provider', 'stripe',
                    'recipient_id', 'acct_update_ticketing',
                    'seller_display_name', 'Update Ticketing Fiscal Sponsor'
                ),
                'require_automatic_tax', true,
                'validated_payment_recipient', jsonb_build_object(
                    'provider', 'stripe',
                    'recipient_id', 'acct_update_ticketing',
                    'seller_display_name', 'Update Ticketing Fiscal Sponsor'
                )
            ),
            'category_id', :'category1ID',
            'description', 'Event seeded for ticketing preservation tests',
            'kind_id', 'virtual',
            'meeting_requested', false,
            'name', 'Paid Virtual Event',
            'timezone', 'UTC',
            'venue_address', '123 Main St',
            'venue_city', 'San Francisco',
            'venue_country_code', 'US',
            'venue_country_name', 'United States',
            'venue_name', 'Community Hall',
            'venue_state_code', 'CA',
            'venue_state_name', 'California',
            'venue_zip_code', '94105'
        )
    ),
    'OCG01',
    'paid ticketing requires an in-person or hybrid event with a complete physical venue',
    'Should reject changing a paid hybrid event to virtual'
);

-- Should reject unrelated edits after payment setup is lost
select throws_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb, null, null)$$,
        :'group1ID',
        :'event19ID',
        jsonb_build_object(
            'category_id', :'category1ID',
            'description', 'Unrelated edits remain available',
            'discount_codes', jsonb_build_array(
                jsonb_build_object(
                    'active', true,
                    'amount_minor', 500,
                    'available_override_active', false,
                    'code', 'SAVE20',
                    'event_discount_code_id', :'event19DiscountCodeID',
                    'kind', 'fixed_amount',
                    'title', 'Launch'
                )
            ),
            'kind_id', 'virtual',
            'meeting_requested', false,
            'name', 'Paid Event Without Payment Setup',
            'payment_currency_code', 'USD',
            'ticket_types', jsonb_build_array(
                jsonb_build_object(
                    'active', true,
                    'availability', 'public',
                    'event_ticket_type_id', :'event19TicketTypeID',
                    'order', 1,
                    'price_windows', jsonb_build_array(
                        jsonb_build_object(
                            'amount_minor', 2500,
                            'event_ticket_price_window_id', :'event19PriceWindowID'
                        )
                    ),
                    'seats_total', 10,
                    'title', 'General'
                )
            ),
            'timezone', 'UTC'
        )
    ),
    'OCG01',
    'payments are not configured on this server',
    'Should reject unrelated edits after payment setup is lost'
);

-- Should accept an unrelated edit echoing a dated configuration without a validation snapshot
select lives_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb, null, 'stripe')$$,
        :'group1ID',
        :'datedEventID',
        jsonb_build_object(
            'category_id', :'category1ID',
            'description', 'Unrelated description edit',
            'discount_codes', jsonb_build_array(
                jsonb_build_object(
                    'active', true,
                    'available_override_active', true,
                    'code', 'DATED10',
                    'ends_at', '2030-06-01T10:00:00.000Z',
                    'event_discount_code_id', :'datedDiscountCodeID',
                    'kind', 'percentage',
                    'percentage', 10,
                    'starts_at', '2030-01-01T10:00:00.000Z',
                    'title', 'Dated',
                    'total_available', 10
                )
            ),
            'kind_id', 'in-person',
            'meeting_requested', false,
            'name', 'Dated Paid Event',
            'payment_currency_code', 'USD',
            'tax_behavior', 'inclusive',
            'tax_calculation_mode', 'none',
            'ticket_types', jsonb_build_array(
                jsonb_build_object(
                    'active', true,
                    'availability', 'public',
                    'event_ticket_type_id', :'datedTicketTypeID',
                    'order', 1,
                    'price_windows', jsonb_build_array(
                        jsonb_build_object(
                            'amount_minor', 2500,
                            'ends_at', '2030-06-01T10:00:00.000Z',
                            'event_ticket_price_window_id', :'datedPriceWindowID',
                            'starts_at', '2030-01-01T10:00:00.000Z'
                        )
                    ),
                    'seats_total', 10,
                    'title', 'General'
                )
            ),
            'timezone', 'UTC',
            'venue_address', '123 Main St',
            'venue_city', 'San Francisco',
            'venue_country_code', 'US',
            'venue_country_name', 'United States',
            'venue_name', 'Community Hall',
            'venue_state_code', 'CA',
            'venue_state_name', 'California',
            'venue_zip_code', '94105'
        )
    ),
    'Should accept an unrelated edit echoing a dated configuration without a validation snapshot'
);
select is(
    (select description from event where event_id = :'datedEventID'::uuid),
    'Unrelated description edit',
    'Should persist the unrelated edit of the dated event'
);
select is(
    (
        select jsonb_build_object(
            'ends_at', etpw.ends_at,
            'starts_at', etpw.starts_at
        )
        from event_ticket_price_window etpw
        where etpw.event_ticket_price_window_id = :'datedPriceWindowID'::uuid
    ),
    jsonb_build_object(
        'ends_at', '2030-06-01 10:00:00+00'::timestamptz,
        'starts_at', '2030-01-01 10:00:00+00'::timestamptz
    ),
    'Should preserve the dated price window instants after the unrelated edit'
);
select is(
    (
        select jsonb_build_object(
            'available', edc.available,
            'available_override_active', edc.available_override_active
        )
        from event_discount_code edc
        where edc.event_discount_code_id = :'datedDiscountCodeID'::uuid
    ),
    jsonb_build_object(
        'available', 4,
        'available_override_active', true
    ),
    'Should preserve the live discount inventory after the unrelated edit'
);

-- Should accept the same unrelated edit under a non-UTC session time zone
set local time zone 'Europe/Madrid';
select lives_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb, null, 'stripe')$$,
        :'group1ID',
        :'datedEventID',
        jsonb_build_object(
            'category_id', :'category1ID',
            'description', 'Unrelated description edit under Madrid',
            'discount_codes', jsonb_build_array(
                jsonb_build_object(
                    'active', true,
                    'available_override_active', true,
                    'code', 'DATED10',
                    'ends_at', '2030-06-01T10:00:00.000Z',
                    'event_discount_code_id', :'datedDiscountCodeID',
                    'kind', 'percentage',
                    'percentage', 10,
                    'starts_at', '2030-01-01T10:00:00.000Z',
                    'title', 'Dated',
                    'total_available', 10
                )
            ),
            'kind_id', 'in-person',
            'meeting_requested', false,
            'name', 'Dated Paid Event',
            'payment_currency_code', 'USD',
            'tax_behavior', 'inclusive',
            'tax_calculation_mode', 'none',
            'ticket_types', jsonb_build_array(
                jsonb_build_object(
                    'active', true,
                    'availability', 'public',
                    'event_ticket_type_id', :'datedTicketTypeID',
                    'order', 1,
                    'price_windows', jsonb_build_array(
                        jsonb_build_object(
                            'amount_minor', 2500,
                            'ends_at', '2030-06-01T10:00:00.000Z',
                            'event_ticket_price_window_id', :'datedPriceWindowID',
                            'starts_at', '2030-01-01T10:00:00.000Z'
                        )
                    ),
                    'seats_total', 10,
                    'title', 'General'
                )
            ),
            'timezone', 'UTC',
            'venue_address', '123 Main St',
            'venue_city', 'San Francisco',
            'venue_country_code', 'US',
            'venue_country_name', 'United States',
            'venue_name', 'Community Hall',
            'venue_state_code', 'CA',
            'venue_state_name', 'California',
            'venue_zip_code', '94105'
        )
    ),
    'Should accept the same unrelated edit under a non-UTC session time zone'
);
set local time zone default;

-- Should persist the Madrid edit while preserving the dated price window instants
select is(
    (
        select jsonb_build_object(
            'description', e.description,
            'ends_at', etpw.ends_at,
            'starts_at', etpw.starts_at
        )
        from event e
        join event_ticket_type ett using (event_id)
        join event_ticket_price_window etpw using (event_ticket_type_id)
        where etpw.event_ticket_price_window_id = :'datedPriceWindowID'::uuid
    ),
    jsonb_build_object(
        'description', 'Unrelated description edit under Madrid',
        'ends_at', '2030-06-01 10:00:00+00'::timestamptz,
        'starts_at', '2030-01-01 10:00:00+00'::timestamptz
    ),
    'Should persist the Madrid edit while preserving the dated price window instants'
);

-- Should reject a shifted dated price window without a validation snapshot
select throws_ok(
    format(
        $$select update_event(null::uuid, %L::uuid, %L::uuid, %L::jsonb, null, 'stripe')$$,
        :'group1ID',
        :'datedEventID',
        jsonb_build_object(
            'category_id', :'category1ID',
            'description', 'Shifted window edit',
            'discount_codes', jsonb_build_array(
                jsonb_build_object(
                    'active', true,
                    'available_override_active', true,
                    'code', 'DATED10',
                    'ends_at', '2030-06-01T10:00:00.000Z',
                    'event_discount_code_id', :'datedDiscountCodeID',
                    'kind', 'percentage',
                    'percentage', 10,
                    'starts_at', '2030-01-01T10:00:00.000Z',
                    'title', 'Dated',
                    'total_available', 10
                )
            ),
            'kind_id', 'in-person',
            'meeting_requested', false,
            'name', 'Dated Paid Event',
            'payment_currency_code', 'USD',
            'tax_behavior', 'inclusive',
            'tax_calculation_mode', 'none',
            'ticket_types', jsonb_build_array(
                jsonb_build_object(
                    'active', true,
                    'availability', 'public',
                    'event_ticket_type_id', :'datedTicketTypeID',
                    'order', 1,
                    'price_windows', jsonb_build_array(
                        jsonb_build_object(
                            'amount_minor', 2500,
                            'ends_at', '2030-06-01T10:00:00.000Z',
                            'event_ticket_price_window_id', :'datedPriceWindowID',
                            'starts_at', '2030-01-01T11:00:00.000Z'
                        )
                    ),
                    'seats_total', 10,
                    'title', 'General'
                )
            ),
            'timezone', 'UTC',
            'venue_address', '123 Main St',
            'venue_city', 'San Francisco',
            'venue_country_code', 'US',
            'venue_country_name', 'United States',
            'venue_name', 'Community Hall',
            'venue_state_code', 'CA',
            'venue_state_name', 'California',
            'venue_zip_code', '94105'
        )
    ),
    'OCG01',
    'payment configuration changed during provider validation',
    'Should reject a shifted dated price window without a validation snapshot'
);

-- Should reject removing every ticket type
select throws_ok(
    format(
        $$select update_event_with_payments(null::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'group1ID',
        :'event19ID',
        jsonb_build_object(
            'category_id', :'category1ID',
            'description', 'Event seeded for ticketing preservation tests',
            'kind_id', 'virtual',
            'name', 'Paid Event Updated',
            'payment_currency_code', 'null'::jsonb,
            'ticket_types', 'null'::jsonb,
            'timezone', 'UTC'
        )
    ),
    'OCG01',
    'events require at least one ticket type',
    'Should reject removing every ticket type'
);

-- Should throw error when a ticket type identifier belongs to another event
select throws_ok(
    format(
        $$select update_event_with_payments(null::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'group1ID',
        :'event19ID',
        jsonb_build_object(
            'category_id', :'category1ID',
            'description', 'Event seeded for ticketing preservation tests',
            'kind_id', 'in-person',
            'name', 'Paid Event Updated',
            'payment_currency_code', 'USD',
            'ticket_types', jsonb_build_array(
                jsonb_build_object(
                    'active', true,
                    'event_ticket_type_id', :'otherTicketTypeID',
                    'order', 1,
                    'price_windows', jsonb_build_array(
                        jsonb_build_object(
                            'amount_minor', 2500,
                            'event_ticket_price_window_id', :'unseededPriceWindowID'
                        )
                    ),
                    'seats_total', 10,
                    'title', 'General'
                )
            ),
            'timezone', 'UTC'
        )
    ),
    'OCG01',
    'ticket type does not belong to event',
    'Should reject ticket types whose identifiers belong to another event'
);

-- Should throw error when a discount code identifier belongs to another event
select throws_ok(
    format(
        $$select update_event_with_payments(null::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'group1ID',
        :'event19ID',
        jsonb_build_object(
            'category_id', :'category1ID',
            'description', 'Event seeded for ticketing preservation tests',
            'discount_codes', jsonb_build_array(
                jsonb_build_object(
                    'active', true,
                    'amount_minor', 250,
                    'code', 'OTHER25',
                    'event_discount_code_id', :'otherDiscountCodeID',
                    'kind', 'fixed_amount',
                    'title', 'Other launch'
                )
            ),
            'kind_id', 'virtual',
            'name', 'Paid Event Updated',
            'timezone', 'UTC'
        )
    ),
    'OCG01',
    'discount code does not belong to event',
    'Should reject discount codes whose identifiers belong to another event'
);

-- Should throw an error when paid tiers omit payment_currency_code
select throws_ok(
    format(
        $$select update_event_with_payments(null::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'group1ID',
        :'event22ID',
        jsonb_build_object(
            'category_id', :'category1ID',
            'description', 'Event used for admission-tier payload validation checks',
            'kind_id', 'virtual',
            'name', 'Admission Payload Event',
            'ticket_types', jsonb_build_array(
                jsonb_build_object(
                    'active', true,
                    'event_ticket_type_id', :'event22MissingCurrencyTicketTypeID',
                    'order', 1,
                    'price_windows', jsonb_build_array(
                        jsonb_build_object(
                            'amount_minor', 2500,
                            'event_ticket_price_window_id', :'event22MissingCurrencyPriceWindowID'
                        )
                    ),
                    'seats_total', 10,
                    'title', 'General'
                )
            ),
            'timezone', 'UTC'
        )
    ),
    'OCG01',
    'paid-capable events require payment_currency_code',
    'Should reject paid-capable events when payment_currency_code is omitted'
);

-- Should allow waitlists with paid admission tiers
select lives_ok(
    format(
        $$select update_event_with_payments(null::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'group1ID',
        :'event22ID',
        jsonb_build_object(
            'category_id', :'category1ID',
            'description', 'Event used for admission-tier payload validation checks',
            'kind_id', 'in-person',
            'name', 'Admission Payload Event',
            'payment_currency_code', 'USD',
            'ticket_types', jsonb_build_array(
                jsonb_build_object(
                    'active', true,
                    'event_ticket_type_id', :'event22WaitlistTicketTypeID',
                    'order', 1,
                    'price_windows', jsonb_build_array(
                        jsonb_build_object(
                            'amount_minor', 2500,
                            'event_ticket_price_window_id', :'event22WaitlistPriceWindowID'
                        )
                    ),
                    'seats_total', 10,
                    'title', 'General'
                )
            ),
            'timezone', 'UTC',
            'venue_address', '123 Main St',
            'venue_city', 'San Francisco',
            'venue_country_code', 'US',
            'venue_name', 'Community Hall',
            'venue_state_code', 'CA',
            'venue_state_name', 'California',
            'venue_zip_code', '94105',
            'waitlist_enabled', true
        )
    ),
    'Should allow paid-tier events when waitlist_enabled stays true'
);

-- Should persist the waitlist with the paid admission tier
select is(
    (
        select jsonb_build_object(
            'amount_minor', etpw.amount_minor,
            'payment_currency_code', e.payment_currency_code,
            'waitlist_enabled', e.waitlist_enabled
        )
        from event e
        join event_ticket_type ett using (event_id)
        join event_ticket_price_window etpw using (event_ticket_type_id)
        where e.event_id = :'event22ID'::uuid
    ),
    jsonb_build_object(
        'amount_minor', 2500,
        'payment_currency_code', 'USD',
        'waitlist_enabled', true
    ),
    'Should persist the waitlist with the paid admission tier'
);

-- Should reject disabling attendee approval while invitation requests are pending
select throws_ok(
    format(
        $$select update_event_with_payments(null::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'group1ID',
        :'event24ID',
        jsonb_build_object(
            'attendee_approval_required', false,
            'category_id', :'category1ID',
            'description', 'Approval-required event used for invitation request checks',
            'kind_id', 'virtual',
            'name', 'Approval Request Event',
            'timezone', 'UTC'
        )
    ),
    'OCG01',
    'approval-required events with pending invitation requests cannot disable approval',
    'Should reject disabling attendee approval while invitation requests are pending'
);

-- Should reject enabling attendee approval while waitlist entries exist
select throws_ok(
    format(
        $$select update_event_with_payments(null::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'group1ID',
        :'event23ID',
        jsonb_build_object(
            'attendee_approval_required', true,
            'capacity', 1,
            'category_id', :'category1ID',
            'description', 'Published event used for ticketing conversion waitlist checks',
            'ends_at', '2030-05-01T12:00:00',
            'kind_id', 'in-person',
            'name', 'Ticketing Waitlist Event',
            'starts_at', '2030-05-01T10:00:00',
            'timezone', 'UTC',
            'waitlist_enabled', false
        )
    ),
    'OCG01',
    'approval-required events cannot have existing waitlist entries',
    'Should reject enabling attendee approval while queued users already exist'
);

-- Should reconcile a public ticket queue after tier capacity increases
select lives_ok(
    format(
        $$select update_event_with_payments(null::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'group1ID',
        :'eventTicketQueueID',
        jsonb_build_object(
            'category_id', :'category1ID',
            'description', 'Published event for ticket queue capacity checks',
            'kind_id', 'in-person',
            'name', 'Ticket Queue Capacity Event',
            'payment_currency_code', 'USD',
            'starts_at', '2030-02-17T10:00:00',
            'ticket_types', jsonb_build_array(
                jsonb_build_object(
                    'active', true,
                    'availability', 'public',
                    'event_ticket_type_id', :'ticketQueueTicketTypeID',
                    'order', 1,
                    'price_windows', jsonb_build_array(
                        jsonb_build_object(
                            'amount_minor', 2500,
                            'event_ticket_price_window_id', :'ticketQueuePriceWindowID'
                        )
                    ),
                    'seats_total', 2,
                    'title', 'Queue General'
                )
            ),
            'timezone', 'UTC',
            'venue_address', '123 Main St',
            'venue_city', 'San Francisco',
            'venue_country_code', 'US',
            'venue_name', 'Community Hall',
            'venue_state_code', 'CA',
            'venue_state_name', 'California',
            'venue_zip_code', '94105'
        )
    ),
    'Should update ticket capacity and reconcile its queue'
);

-- Should assign the newly available ticket seat to the FIFO queue head
select is(
    (
        select jsonb_build_object(
            'offer_status', (
                select status
                from admission_offer
                where event_id = :'eventTicketQueueID'::uuid
                and user_id = :'user4ID'::uuid
            ),
            'seats_total', (
                select seats_total
                from event_ticket_type
                where event_ticket_type_id = :'ticketQueueTicketTypeID'::uuid
            ),
            'waitlist_count', (
                select count(*)
                from event_waitlist
                where event_id = :'eventTicketQueueID'::uuid
            )
        )
    ),
    '{"offer_status":"pending","seats_total":2,"waitlist_count":0}'::jsonb,
    'Should promote the ticket queue after capacity increases'
);

-- Should update registration questions while the event is unpublished
select lives_ok(
    format(
        $$select update_event_with_payments(%L::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'questionsOrganizerUserID',
        :'questionsGroupID',
        :'eventQuestionsID',
        jsonb_build_object(
            'category_id', :'questionsEventCategoryID',
            'description', 'Desc',
            'kind_id', 'in-person',
            'name', 'Draft Questions Event',
            'registration_questions', jsonb_build_array(
                jsonb_build_object(
                    'id', :'registrationQuestionID',
                    'kind', 'free-text',
                    'options', '[]'::jsonb,
                    'prompt', 'Original',
                    'required', true
                )
            ),
            'starts_at', '2030-01-01T10:00:00Z',
            'timezone', 'UTC'
        )
    ),
    'Should update registration questions while the event is unpublished'
);

-- Should store updated registration questions
select is(
    (
        select registration_questions
        from event
        where event_id = :'eventQuestionsID'::uuid
    ),
    jsonb_build_array(
        jsonb_build_object(
            'id', :'registrationQuestionID',
            'kind', 'free-text',
            'options', '[]'::jsonb,
            'prompt', 'Original',
            'required', true
        )
    ),
    'Should store updated registration questions'
);

-- Should validate registration questions when updating an event
select throws_ok(
    format(
        $$select update_event_with_payments(%L::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'questionsOrganizerUserID',
        :'questionsGroupID',
        :'eventQuestionsID',
        jsonb_build_object(
            'category_id', :'questionsEventCategoryID',
            'description', 'Desc',
            'kind_id', 'in-person',
            'name', 'Draft Questions Event',
            'registration_questions', jsonb_build_array(
                jsonb_build_object(
                    'id', 'bad',
                    'kind', 'free-text',
                    'options', '[]'::jsonb,
                    'prompt', 'Invalid',
                    'required', true
                )
            ),
            'starts_at', '2030-01-01T10:00:00Z',
            'timezone', 'UTC'
        )
    ),
    'OCG01',
    'questionnaire question id must be a uuid',
    'Should validate registration questions when updating an event'
);

-- Should update registration questions after publish when no answers exist
select lives_ok(
    format(
        $$select update_event_with_payments(%L::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'questionsOrganizerUserID',
        :'questionsGroupID',
        :'eventQuestionsPublishedID',
        jsonb_build_object(
            'category_id', :'questionsEventCategoryID',
            'description', 'Desc',
            'kind_id', 'in-person',
            'name', 'Published Questions Event',
            'registration_questions', jsonb_build_array(
                jsonb_build_object(
                    'id', :'registrationQuestionID',
                    'kind', 'free-text',
                    'options', '[]'::jsonb,
                    'prompt', 'Changed',
                    'required', true
                )
            ),
            'starts_at', '2030-01-01T10:00:00Z',
            'timezone', 'UTC'
        )
    ),
    'Should update registration questions after publish when no answers exist'
);

-- Should store the registration questions changed after publish
select is(
    (
        select registration_questions
        from event
        where event_id = :'eventQuestionsPublishedID'::uuid
    ),
    jsonb_build_array(
        jsonb_build_object(
            'id', :'registrationQuestionID',
            'kind', 'free-text',
            'options', '[]'::jsonb,
            'prompt', 'Changed',
            'required', true
        )
    ),
    'Should store the registration questions changed after publish'
);

-- Should preserve registration questions when answers exist and questions are omitted
select lives_ok(
    format(
        $$select update_event_with_payments(%L::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'questionsOrganizerUserID',
        :'questionsGroupID',
        :'eventQuestionsAnsweredID',
        jsonb_build_object(
            'category_id', :'questionsEventCategoryID',
            'description', 'Desc',
            'kind_id', 'in-person',
            'name', 'Answered Questions Event Updated',
            'starts_at', '2030-01-01T10:00:00Z',
            'timezone', 'UTC'
        )
    ),
    'Should preserve registration questions when answers exist and questions are omitted'
);

-- Should keep the seeded registration questions when they are omitted
select is(
    (
        select jsonb_build_object(
            'name', name,
            'registration_questions', registration_questions
        )
        from event
        where event_id = :'eventQuestionsAnsweredID'::uuid
    ),
    jsonb_build_object(
        'name', 'Answered Questions Event Updated',
        'registration_questions', jsonb_build_array(
            jsonb_build_object(
                'id', :'registrationQuestionID',
                'kind', 'free-text',
                'options', '[]'::jsonb,
                'prompt', 'Original',
                'required', true
            )
        )
    ),
    'Should keep the seeded registration questions when they are omitted'
);

-- Should reject registration question changes after answers exist
select throws_ok(
    format(
        $$select update_event_with_payments(%L::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'questionsOrganizerUserID',
        :'questionsGroupID',
        :'eventQuestionsAnsweredID',
        jsonb_build_object(
            'category_id', :'questionsEventCategoryID',
            'description', 'Desc',
            'kind_id', 'in-person',
            'name', 'Answered Questions Event',
            'registration_questions', jsonb_build_array(
                jsonb_build_object(
                    'id', :'registrationQuestionID',
                    'kind', 'free-text',
                    'options', '[]'::jsonb,
                    'prompt', 'Changed',
                    'required', true
                )
            ),
            'starts_at', '2030-01-01T10:00:00Z',
            'timezone', 'UTC'
        )
    ),
    'OCG01',
    'registration questions cannot be changed after attendees have submitted answers',
    'Should reject registration question changes after answers exist'
);

-- Should allow unrelated event edits while checkout holds are active
select lives_ok(
    format(
        $$select update_event_with_payments(%L::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'questionsOrganizerUserID',
        :'questionsGroupID',
        :'eventQuestionsHoldID',
        jsonb_build_object(
            'category_id', :'questionsEventCategoryID',
            'description', 'Desc',
            'kind_id', 'in-person',
            'name', 'Held Questions Event Updated',
            'starts_at', '2030-01-01T10:00:00Z',
            'timezone', 'UTC',
            'venue_address', '123 Main St',
            'venue_city', 'San Francisco',
            'venue_country_code', 'US',
            'venue_name', 'Community Hall',
            'venue_state_code', 'CA',
            'venue_state_name', 'California',
            'venue_zip_code', '94105'
        )
    ),
    'Should allow unrelated event edits while checkout holds are active'
);

-- Should store the unrelated edit and keep the held registration questions
select is(
    (
        select jsonb_build_object(
            'name', name,
            'registration_questions', registration_questions
        )
        from event
        where event_id = :'eventQuestionsHoldID'::uuid
    ),
    jsonb_build_object(
        'name', 'Held Questions Event Updated',
        'registration_questions', jsonb_build_array(
            jsonb_build_object(
                'id', :'registrationQuestionID',
                'kind', 'free-text',
                'options', '[]'::jsonb,
                'prompt', 'Original',
                'required', true
            )
        )
    ),
    'Should store the unrelated edit and keep the held registration questions'
);

-- Should reject registration question changes while checkout holds are active
select throws_ok(
    format(
        $$select update_event_with_payments(%L::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'questionsOrganizerUserID',
        :'questionsGroupID',
        :'eventQuestionsHoldID',
        jsonb_build_object(
            'category_id', :'questionsEventCategoryID',
            'description', 'Desc',
            'kind_id', 'in-person',
            'name', 'Held Questions Event Updated',
            'registration_questions', jsonb_build_array(
                jsonb_build_object(
                    'id', :'registrationQuestionID',
                    'kind', 'free-text',
                    'options', '[]'::jsonb,
                    'prompt', 'Changed',
                    'required', true
                )
            ),
            'starts_at', '2030-01-01T10:00:00Z',
            'timezone', 'UTC'
        )
    ),
    'OCG01',
    'registration questions cannot be changed while checkout holds are active',
    'Should reject registration question changes while checkout holds are active'
);

-- Should clear payment-only configuration when the final positive price is removed
select lives_ok(
    format(
        $$select update_event_with_payments(null::uuid, %L::uuid, %L::uuid, %L::jsonb)$$,
        :'group1ID',
        :'event19ID',
        jsonb_build_object(
            'category_id', :'category1ID',
            'description', 'Event seeded for ticketing preservation tests',
            'discount_codes', 'null'::jsonb,
            'kind_id', 'virtual',
            'name', 'Paid Event Updated',
            'ticket_types', jsonb_build_array(
                jsonb_build_object(
                    'active', true,
                    'availability', 'public',
                    'event_ticket_type_id', :'event19TicketTypeID',
                    'order', 1,
                    'price_windows', jsonb_build_array(
                        jsonb_build_object(
                            'amount_minor', 0,
                            'event_ticket_price_window_id', :'event19PriceWindowID'
                        )
                    ),
                    'seats_total', 10,
                    'title', 'General'
                )
            ),
            'timezone', 'UTC'
        )
    ),
    'Should clear payment-only configuration with the final positive price'
);

-- Should persist the provider-free configuration with its free ticket tier
select results_eq(
    format(
        $$
            select
                payment_currency_code,
                (select count(*)::int from event_discount_code where event_id = e.event_id),
                (select count(*)::int from event_ticket_type where event_id = e.event_id)
            from event e
            where event_id = %L::uuid
        $$,
        :'event19ID'
    ),
    $$ values (null::text, 0::int, 1::int) $$,
    'Should persist provider-free configuration with its free ticket tier'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
