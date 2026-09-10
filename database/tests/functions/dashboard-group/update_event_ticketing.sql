-- Tests updating event ticketing configuration.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(32);

-- ============================================================================
-- VARIABLES
-- ============================================================================
\set category1ID '3a3c0000-0000-0000-0000-000000000001'
\set community1ID '3a3c0000-0000-0000-0000-000000000002'
\set event13ID '3a3c0000-0000-0000-0000-000000000003'
\set event14ID '3a3c0000-0000-0000-0000-000000000004'
\set event15ID '3a3c0000-0000-0000-0000-000000000005'
\set event16ID '3a3c0000-0000-0000-0000-000000000006'
\set event17ID '3a3c0000-0000-0000-0000-000000000007'
\set event19ID '3a3c0000-0000-0000-0000-000000000008'
\set event20ID '3a3c0000-0000-0000-0000-000000000009'
\set event21ID '3a3c0000-0000-0000-0000-000000000010'
\set event22ID '3a3c0000-0000-0000-0000-000000000011'
\set event23ID '3a3c0000-0000-0000-0000-000000000012'
\set event24ID '3a3c0000-0000-0000-0000-000000000013'
\set eventOverCapacityID '3a3c0000-0000-0000-0000-000000000014'
\set eventPaidTransitionID '3a3c0000-0000-0000-0000-000000000068'
\set eventQuestionsAnsweredID '3a3c0000-0000-0000-0000-000000000015'
\set eventQuestionsHoldID '3a3c0000-0000-0000-0000-000000000056'
\set eventQuestionsID '3a3c0000-0000-0000-0000-000000000016'
\set eventQuestionsPublishedID '3a3c0000-0000-0000-0000-000000000017'
\set eventTicketQueueID '3a3c0000-0000-0000-0000-000000000064'
\set group1ID '3a3c0000-0000-0000-0000-000000000018'
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
\set paidTransitionPriceWindowID '3a3c0000-0000-0000-0000-00000000006a'
\set paidTransitionTicketTypeID '3a3c0000-0000-0000-0000-000000000069'
\set ticketQueuePriceWindowID '3a3c0000-0000-0000-0000-000000000065'
\set ticketQueuePurchaseID '3a3c0000-0000-0000-0000-000000000066'
\set ticketQueueTicketTypeID '3a3c0000-0000-0000-0000-000000000067'
\set user1ID '3a3c0000-0000-0000-0000-000000000025'
\set user2ID '3a3c0000-0000-0000-0000-000000000026'
\set user3ID '3a3c0000-0000-0000-0000-000000000027'
\set user4ID '3a3c0000-0000-0000-0000-000000000028'
\set user5ID '3a3c0000-0000-0000-0000-000000000029'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories, event categories and users
select fx_community(:'community1ID');
select fx_community(:'questionsCommunityID');
select fx_group_category('3a3c0000-0000-0000-0000-000000000030', :'community1ID');
select fx_group_category(:'questionsCategoryID', :'questionsCommunityID');
select fx_event_category(:'category1ID', :'community1ID');
select fx_event_category(:'questionsEventCategoryID', :'questionsCommunityID');
select fx_user(:'user1ID');
select fx_user(:'user2ID');
select fx_user(:'user3ID');
select fx_user(:'user4ID');
select fx_user(:'user5ID');
select fx_user(:'questionsOrganizerUserID');
select fx_user(:'questionsAttendeeUserID');
select fx_user(:'questionsHoldUserID');

-- Group
select fx_group(:'group1ID', :'community1ID', '3a3c0000-0000-0000-0000-000000000030', jsonb_build_object('payment_recipient', '{"provider": "stripe", "recipient_id": "acct_update_ticketing", "seller_display_name": "Update Ticketing Fiscal Sponsor"}'::jsonb));

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
        'id', '3a3c0000-0000-0000-0000-000000000031',
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
        'id', '3a3c0000-0000-0000-0000-000000000031',
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
        'id', '3a3c0000-0000-0000-0000-000000000031',
        'kind', 'free-text',
        'options', '[]'::jsonb,
        'prompt', 'Original',
        'required', true
    )),
    'starts_at', '2030-01-01 10:00:00+00'
));

-- Published event for waitlist promotion checks
select fx_event(:'event13ID', :'group1ID', :'category1ID', jsonb_build_object(
    'capacity', 1,
    'published', true,
    'starts_at', '2030-02-01 10:00:00+00',
    'waitlist_enabled', true
));

-- Published event used for attendee floor validation checks
select fx_event(:'event14ID', :'group1ID', :'category1ID', jsonb_build_object(
    'capacity', 3,
    'published', true,
    'starts_at', '2030-02-10 10:00:00-05',
    'timezone', 'America/New_York'
));

-- Published event used for waitlist promotion on capacity increase
select fx_event(:'event15ID', :'group1ID', :'category1ID', jsonb_build_object(
    'capacity', 3,
    'ends_at', '2030-03-01 12:00:00-05',
    'published', true,
    'starts_at', '2030-03-01 10:00:00-05',
    'timezone', 'America/New_York',
    'waitlist_enabled', true
));

-- Published event used when waitlist is disabled for new joins
select fx_event(:'event16ID', :'group1ID', :'category1ID', jsonb_build_object(
    'capacity', 2,
    'published', true,
    'starts_at', '2030-02-16 10:00:00+00',
    'waitlist_enabled', true
));

-- Published event already over capacity because of a confirmed manual invitation
select fx_event(:'eventOverCapacityID', :'group1ID', :'category1ID', jsonb_build_object(
    'capacity', 2,
    'published', true,
    'starts_at', '2030-02-12 10:00:00+00'
));

-- Published event used when capacity becomes unlimited
select fx_event(:'event17ID', :'group1ID', :'category1ID', jsonb_build_object(
    'capacity', 1,
    'published', true,
    'starts_at', '2030-02-17 10:00:00+00',
    'waitlist_enabled', true
));

-- Published event used for ticketing conversion without waitlist promotion
select fx_event(:'event20ID', :'group1ID', :'category1ID', jsonb_build_object(
    'capacity', 1,
    'ends_at', '2030-04-01 12:00:00-04',
    'published', true,
    'starts_at', '2030-04-01 10:00:00-04',
    'timezone', 'America/New_York',
    'waitlist_enabled', true
));

-- Event used for admission-tier payload validation checks
select fx_event(:'event22ID', :'group1ID', :'category1ID', jsonb_build_object(
    'description', 'Event used for admission-tier payload validation checks',
    'event_kind_id', 'virtual',
    'name', 'Admission Payload Event'
));

-- Published event used for ticketing conversion waitlist checks
select fx_event(:'event23ID', :'group1ID', :'category1ID', jsonb_build_object(
    'capacity', 1,
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
    'capacity', 10,
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

-- Paid event used for purchased ticketing guard checks
select fx_event(:'event21ID', :'group1ID', :'category1ID', jsonb_build_object(
    'capacity', 10,
    'description', 'Paid event used for purchased ticketing guard checks',
    'event_kind_id', 'virtual',
    'name', 'Protected Paid Event',
    'payment_currency_code', 'USD'
));

-- Separate event used only for ticketing ownership checks
select fx_event('3a3c0000-0000-0000-0000-000000000032'::uuid, :'group1ID', :'category1ID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'payment_currency_code', 'USD'
));

-- Paid in-person event used for event-kind transition checks
select fx_event(:'eventPaidTransitionID', :'group1ID', :'category1ID', jsonb_build_object(
    'capacity', 10,
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
    'capacity', 1,
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
select fx_event_ticket_type('3a3c0000-0000-0000-0000-000000000033'::uuid, :'event19ID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General'
));

-- Price window for the primary event ticket type
select fx_event_ticket_price_window('3a3c0000-0000-0000-0000-000000000034'::uuid, '3a3c0000-0000-0000-0000-000000000033'::uuid, jsonb_build_object('amount_minor', 2500));

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
    '3a3c0000-0000-0000-0000-000000000035'::uuid,
    true,
    500,
    'SAVE20',
    :'event19ID',
    'fixed_amount',
    'Launch'
);

-- Protected ticket type referenced by a completed purchase
select fx_event_ticket_type('3a3c0000-0000-0000-0000-000000000036'::uuid, :'event21ID', jsonb_build_object(
    'seats_total', 10,
    'title', 'Protected General'
));

-- Price window for the protected general ticket type
select fx_event_ticket_price_window('3a3c0000-0000-0000-0000-000000000037'::uuid, '3a3c0000-0000-0000-0000-000000000036'::uuid, jsonb_build_object('amount_minor', 2500));

-- Second protected ticket type used by synchronization scenarios
select fx_event_ticket_type('3a3c0000-0000-0000-0000-000000000038'::uuid, :'event21ID', jsonb_build_object(
    'order', 2,
    'seats_total', 5,
    'title', 'Protected VIP'
));

-- Price window for the protected VIP ticket type
select fx_event_ticket_price_window('3a3c0000-0000-0000-0000-000000000039'::uuid, '3a3c0000-0000-0000-0000-000000000038'::uuid, jsonb_build_object('amount_minor', 5000));

-- Protected discount code referenced by a completed purchase
insert into event_discount_code (
    event_discount_code_id,
    active,
    amount_minor,
    code,
    event_id,
    kind,
    title,
    total_available
) values (
    '3a3c0000-0000-0000-0000-000000000040'::uuid,
    true,
    500,
    'PROTECT5',
    :'event21ID',
    'fixed_amount',
    'Protected launch',
    5
);

-- Ticketing rows on a different event used for ownership checks
select fx_event_ticket_type('3a3c0000-0000-0000-0000-000000000041'::uuid, '3a3c0000-0000-0000-0000-000000000032'::uuid, jsonb_build_object(
    'seats_total', 25
));

-- Price window owned by the other event
select fx_event_ticket_price_window('3a3c0000-0000-0000-0000-000000000042'::uuid, '3a3c0000-0000-0000-0000-000000000041'::uuid, jsonb_build_object('amount_minor', 3000));

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
    '3a3c0000-0000-0000-0000-000000000043'::uuid,
    true,
    250,
    'OTHER25',
    '3a3c0000-0000-0000-0000-000000000032'::uuid,
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

-- Completed purchase that protects ticketing rows from removal
insert into event_purchase (
    amount_minor,
    currency_code,
    discount_code,
    event_discount_code_id,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id
) values (
    0,
    'USD',
    'PROTECT5',
    '3a3c0000-0000-0000-0000-000000000040'::uuid,
    :'event21ID',
    '3a3c0000-0000-0000-0000-000000000036'::uuid,
    'completed',
    'Protected General',
    :'user1ID'
);

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

-- Every event uses ticket inventory. Seed a default free tier for events that
-- are not exercising an explicit ticket configuration in this test
select fx_event_ticket_type(
    gen_random_uuid(),
    e.event_id,
    jsonb_build_object(
        'seats_total', greatest(coalesce(e.capacity, 100), 1)
    )
)
from event e
where not exists (
    select 1
    from event_ticket_type ett
    where ett.event_id = e.event_id
);

-- Current free prices for the default ticket tiers
select fx_event_ticket_price_window(
    gen_random_uuid(),
    ett.event_ticket_type_id,
    jsonb_build_object('amount_minor', 0)
)
from event_ticket_type ett
where not exists (
    select 1
    from event_ticket_price_window etpw
    where etpw.event_ticket_type_id = ett.event_ticket_type_id
);

-- Event Attendees (for capacity validation and waitlist promotion tests)
insert into event_attendee (event_id, user_id) values
    (:'event13ID', :'user2ID'),
    (:'event14ID', :'user1ID'),
    (:'event14ID', :'user2ID'),
    (:'event14ID', :'user3ID'),
    (:'event15ID', :'user1ID'),
    (:'event15ID', :'user2ID'),
    (:'event15ID', :'user3ID'),
    (:'event16ID', :'user2ID'),
    (:'event16ID', :'user3ID'),
    (:'event17ID', :'user2ID'),
    (:'event20ID', :'user1ID');

-- Over-capacity event attendees with one organizer-controlled manual seat
insert into event_attendee (event_id, user_id, manually_invited, status) values
    (:'eventOverCapacityID', :'user1ID', false, 'confirmed'),
    (:'eventOverCapacityID', :'user2ID', false, 'confirmed'),
    (:'eventOverCapacityID', :'user3ID', true, 'confirmed');

-- Attendee with answers that lock registration questions
insert into event_attendee (event_id, user_id, registration_answers, status)
values (
    :'eventQuestionsAnsweredID',
    :'questionsAttendeeUserID',
    jsonb_build_object(
        'answers',
        jsonb_build_array(jsonb_build_object(
            'question_id', '3a3c0000-0000-0000-0000-000000000031',
            'value', 'Answer'
        ))
    ),
    'confirmed'
);

-- Event Waitlist (for waitlist promotion tests)
insert into event_waitlist (
    created_at,
    event_id,
    event_ticket_type_id,
    user_id
)
select
    waitlisted.created_at,
    waitlisted.event_id,
    (
        select ett.event_ticket_type_id
        from event_ticket_type ett
        where ett.event_id = waitlisted.event_id
        order by ett."order", ett.event_ticket_type_id
        limit 1
    ),
    waitlisted.user_id
from (
    values
        (:'event13ID'::uuid, :'user3ID'::uuid, current_timestamp),
        (:'event15ID'::uuid, :'user4ID'::uuid, current_timestamp),
        (:'event15ID'::uuid, :'user5ID'::uuid, current_timestamp + interval '1 minute'),
        (:'event16ID'::uuid, :'user1ID'::uuid, current_timestamp + interval '2 minutes'),
        (:'event17ID'::uuid, :'user4ID'::uuid, current_timestamp + interval '3 minutes'),
        (:'event17ID'::uuid, :'user5ID'::uuid, current_timestamp + interval '4 minutes'),
        (:'event20ID'::uuid, :'user4ID'::uuid, current_timestamp + interval '5 minutes'),
        (:'event23ID'::uuid, :'user5ID'::uuid, current_timestamp + interval '6 minutes')
) as waitlisted(event_id, user_id, created_at);

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

-- Event invitation requests (for attendee approval transition tests)
insert into event_invitation_request (
    event_id,
    event_ticket_type_id,
    user_id
)
select
    :'event24ID',
    ett.event_ticket_type_id,
    :'user5ID'
from event_ticket_type ett
where ett.event_id = :'event24ID'
order by ett."order", ett.event_ticket_type_id
limit 1;

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
    $$select update_event_with_payments(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000008'::uuid,
        '{
            "name": "Paid Event Updated",
            "description": "Event seeded for ticketing preservation tests",
            "timezone": "UTC",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "kind_id": "in-person",
            "meeting_requested": false,
            "venue_address": "123 Main St",
            "venue_city": "San Francisco",
            "venue_country_code": "US",
            "venue_name": "Community Hall",
            "venue_state_code": "CA",
            "venue_state_name": "California",
            "venue_zip_code": "94105"
        }'::jsonb
    )$$,
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
    '{
        "discount_codes": [
            {
                "active": true,
                "amount_minor": 500,
                "available_override_active": false,
                "code": "SAVE20",
                "event_discount_code_id": "3a3c0000-0000-0000-0000-000000000035",
                "kind": "fixed_amount",
                "title": "Launch"
            }
        ],
        "payment_currency_code": "USD",
        "ticket_types": [
            {
                "active": true,
                "availability": "public",
                "current_price": {
                    "amount_minor": 2500
                },
                "event_ticket_type_id": "3a3c0000-0000-0000-0000-000000000033",
                "order": 1,
                "price_windows": [
                    {
                        "amount_minor": 2500,
                        "event_ticket_price_window_id": "3a3c0000-0000-0000-0000-000000000034"
                    }
                ],
                "remaining_seats": 10,
                "seats_total": 10,
                "sold_out": false,
                "title": "General"
            }
        ]
    }'::jsonb,
    'Should keep ticketing fields when payload omits payment controls'
);
select is(
    (select capacity from event where event_id = :'event19ID'::uuid),
    10,
    'Should preserve derived capacity when payload omits payment controls'
);

-- Should allow an in-person paid event to become hybrid
select lives_ok(
    $$select update_event_with_payments(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000068'::uuid,
        '{
            "_payment_validation": {
                "expected_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_update_ticketing",
                    "seller_display_name": "Update Ticketing Fiscal Sponsor"
                },
                "require_automatic_tax": true,
                "validated_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_update_ticketing",
                    "seller_display_name": "Update Ticketing Fiscal Sponsor"
                }
            },
            "name": "Paid Hybrid Event",
            "description": "Event seeded for ticketing preservation tests",
            "timezone": "UTC",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "kind_id": "hybrid",
            "meeting_requested": false,
            "venue_address": "123 Main St",
            "venue_city": "San Francisco",
            "venue_country_code": "US",
            "venue_country_name": "United States",
            "venue_name": "Community Hall",
            "venue_state_code": "CA",
            "venue_state_name": "California",
            "venue_zip_code": "94105"
        }'::jsonb
    )$$,
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
    $$select update_event_with_payments(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000068'::uuid,
        '{
            "_payment_validation": {
                "expected_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_update_ticketing",
                    "seller_display_name": "Update Ticketing Fiscal Sponsor"
                },
                "require_automatic_tax": true,
                "validated_payment_recipient": {
                    "provider": "stripe",
                    "recipient_id": "acct_update_ticketing",
                    "seller_display_name": "Update Ticketing Fiscal Sponsor"
                }
            },
            "name": "Paid Virtual Event",
            "description": "Event seeded for ticketing preservation tests",
            "timezone": "UTC",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "kind_id": "virtual",
            "meeting_requested": false,
            "venue_address": "123 Main St",
            "venue_city": "San Francisco",
            "venue_country_code": "US",
            "venue_country_name": "United States",
            "venue_name": "Community Hall",
            "venue_state_code": "CA",
            "venue_state_name": "California",
            "venue_zip_code": "94105"
        }'::jsonb
    )$$,
    'OCG01',
    'paid ticketing requires an in-person or hybrid event with a complete physical venue',
    'Should reject changing a paid hybrid event to virtual'
);

-- Should reject unrelated edits after payment setup is lost
select throws_ok(
    $$
        select update_event(
            null::uuid,
            '3a3c0000-0000-0000-0000-000000000018'::uuid,
            '3a3c0000-0000-0000-0000-000000000008'::uuid,
            '{
                "name": "Paid Event Without Payment Setup",
                "description": "Unrelated edits remain available",
                "timezone": "UTC",
                "category_id": "3a3c0000-0000-0000-0000-000000000001",
                "kind_id": "virtual",
                "meeting_requested": false,
                "payment_currency_code": "USD",
                "discount_codes": [
                    {
                        "active": true,
                        "amount_minor": 500,
                        "available_override_active": false,
                        "code": "SAVE20",
                        "event_discount_code_id": "3a3c0000-0000-0000-0000-000000000035",
                        "kind": "fixed_amount",
                        "title": "Launch"
                    }
                ],
                "ticket_types": [
                    {
                        "active": true,
                        "availability": "public",
                        "event_ticket_type_id": "3a3c0000-0000-0000-0000-000000000033",
                        "order": 1,
                        "price_windows": [
                            {
                                "amount_minor": 2500,
                                "event_ticket_price_window_id": "3a3c0000-0000-0000-0000-000000000034"
                            }
                        ],
                        "seats_total": 10,
                        "title": "General"
                    }
                ]
            }'::jsonb,
            null,
            null
        )
    $$,
    'OCG01',
    'payments are not configured on this server',
    'Should reject unrelated edits after payment setup is lost'
);

-- Should reject removing every ticket type
select throws_ok(
    $$select update_event_with_payments(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000008'::uuid,
        '{
            "name": "Paid Event Updated",
            "description": "Event seeded for ticketing preservation tests",
            "timezone": "UTC",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "kind_id": "virtual",
            "payment_currency_code": null,
            "ticket_types": null
        }'::jsonb
    )$$,
    'OCG01',
    'events require at least one ticket type',
    'Should reject removing every ticket type'
);

-- Should throw error when a ticket type identifier belongs to another event
select throws_ok(
    $$select update_event_with_payments(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000008'::uuid,
        '{
            "name": "Paid Event Updated",
            "description": "Event seeded for ticketing preservation tests",
            "timezone": "UTC",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "kind_id": "in-person",
            "payment_currency_code": "USD",
            "ticket_types": [
                {
                    "active": true,
                    "event_ticket_type_id": "3a3c0000-0000-0000-0000-000000000041",
                    "order": 1,
                    "price_windows": [
                        {
                            "amount_minor": 2500,
                            "event_ticket_price_window_id": "3a3c0000-0000-0000-0000-000000000044"
                        }
                    ],
                    "seats_total": 10,
                    "title": "General"
                }
            ]
        }'::jsonb
    )$$,
    'OCG01',
    'ticket type does not belong to event',
    'Should reject ticket types whose identifiers belong to another event'
);

-- Should throw error when a ticket price window identifier belongs to another event
select throws_ok(
    $$select update_event_with_payments(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000008'::uuid,
        '{
            "name": "Paid Event Updated",
            "description": "Event seeded for ticketing preservation tests",
            "timezone": "UTC",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "kind_id": "virtual",
            "payment_currency_code": "USD",
            "ticket_types": [
                {
                    "active": true,
                    "event_ticket_type_id": "3a3c0000-0000-0000-0000-000000000033",
                    "order": 1,
                    "price_windows": [
                        {
                            "amount_minor": 2500,
                            "event_ticket_price_window_id": "3a3c0000-0000-0000-0000-000000000042"
                        }
                    ],
                    "seats_total": 10,
                    "title": "General"
                }
            ]
        }'::jsonb
    )$$,
    'OCG01',
    'ticket price window does not belong to event',
    'Should reject ticket price windows whose identifiers belong to another event'
);

-- Should throw error when a ticket price window identifier belongs to another ticket type
select throws_ok(
    $$select update_event_with_payments(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000010'::uuid,
        '{
            "name": "Protected Paid Event",
            "description": "Paid event used for purchased ticketing guard checks",
            "timezone": "UTC",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "kind_id": "virtual",
            "payment_currency_code": "USD",
            "ticket_types": [
                {
                    "active": true,
                    "event_ticket_type_id": "3a3c0000-0000-0000-0000-000000000036",
                    "order": 1,
                    "price_windows": [
                        {
                            "amount_minor": 2500,
                            "event_ticket_price_window_id": "3a3c0000-0000-0000-0000-000000000039"
                        }
                    ],
                    "seats_total": 10,
                    "title": "Protected General"
                },
                {
                    "active": true,
                    "event_ticket_type_id": "3a3c0000-0000-0000-0000-000000000038",
                    "order": 2,
                    "price_windows": [
                        {
                            "amount_minor": 5000,
                            "event_ticket_price_window_id": "3a3c0000-0000-0000-0000-000000000039"
                        }
                    ],
                    "seats_total": 5,
                    "title": "Protected VIP"
                }
            ]
        }'::jsonb
    )$$,
    'OCG01',
    'ticket price window does not belong to ticket type',
    'Should reject ticket price windows whose identifiers belong to another ticket type'
);

-- Should throw error when a discount code identifier belongs to another event
select throws_ok(
    $$select update_event_with_payments(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000008'::uuid,
        '{
            "name": "Paid Event Updated",
            "description": "Event seeded for ticketing preservation tests",
            "timezone": "UTC",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "discount_codes": [
                {
                    "active": true,
                    "amount_minor": 250,
                    "code": "OTHER25",
                    "event_discount_code_id": "3a3c0000-0000-0000-0000-000000000043",
                    "kind": "fixed_amount",
                    "title": "Other launch"
                }
            ],
            "kind_id": "virtual"
        }'::jsonb
    )$$,
    'OCG01',
    'discount code does not belong to event',
    'Should reject discount codes whose identifiers belong to another event'
);

-- Should throw an error when paid tiers omit payment_currency_code
select throws_ok(
    $$select update_event_with_payments(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000011'::uuid,
        '{
            "name": "Admission Payload Event",
            "description": "Event used for admission-tier payload validation checks",
            "timezone": "UTC",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "kind_id": "virtual",
            "ticket_types": [
                {
                    "active": true,
                    "event_ticket_type_id": "3a3c0000-0000-0000-0000-000000000047",
                    "order": 1,
                    "price_windows": [
                        {
                            "amount_minor": 2500,
                            "event_ticket_price_window_id": "3a3c0000-0000-0000-0000-000000000048"
                        }
                    ],
                    "seats_total": 10,
                    "title": "General"
                }
            ]
        }'::jsonb
    )$$,
    'OCG01',
    'paid-capable events require payment_currency_code',
    'Should reject paid-capable events when payment_currency_code is omitted'
);

-- Should allow waitlists with paid admission tiers
select lives_ok(
    $$select update_event_with_payments(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000011'::uuid,
        '{
            "name": "Admission Payload Event",
            "description": "Event used for admission-tier payload validation checks",
            "timezone": "UTC",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "kind_id": "in-person",
            "payment_currency_code": "USD",
            "ticket_types": [
                {
                    "active": true,
                    "event_ticket_type_id": "3a3c0000-0000-0000-0000-000000000049",
                    "order": 1,
                    "price_windows": [
                        {
                            "amount_minor": 2500,
                            "event_ticket_price_window_id": "3a3c0000-0000-0000-0000-000000000050"
                        }
                    ],
                    "seats_total": 10,
                    "title": "General"
                }
            ],
            "venue_address": "123 Main St",
            "venue_city": "San Francisco",
            "venue_country_code": "US",
            "venue_name": "Community Hall",
            "venue_state_code": "CA",
            "venue_state_name": "California",
            "venue_zip_code": "94105",
            "waitlist_enabled": true
        }'::jsonb
    )$$,
    'Should allow paid-tier events when waitlist_enabled stays true'
);

-- Should reject disabling attendee approval while invitation requests are pending
select throws_ok(
    $$select update_event_with_payments(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000013'::uuid,
        '{
            "name": "Approval Request Event",
            "description": "Approval-required event used for invitation request checks",
            "timezone": "UTC",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "kind_id": "virtual",
            "attendee_approval_required": false
        }'::jsonb
    )$$,
    'OCG01',
    'approval-required events with pending invitation requests cannot disable approval',
    'Should reject disabling attendee approval while invitation requests are pending'
);

-- Should reject enabling attendee approval while waitlist entries exist
select throws_ok(
    $$select update_event_with_payments(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000012'::uuid,
        '{
            "name": "Ticketing Waitlist Event",
            "description": "Published event used for ticketing conversion waitlist checks",
            "timezone": "UTC",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "kind_id": "in-person",
            "attendee_approval_required": true,
            "capacity": 1,
            "ends_at": "2030-05-01T12:00:00",
            "starts_at": "2030-05-01T10:00:00",
            "waitlist_enabled": false
        }'::jsonb
    )$$,
    'OCG01',
    'approval-required events cannot have existing waitlist entries',
    'Should reject enabling attendee approval while queued users already exist'
);

-- Should throw error when ticket seats are reduced below purchased inventory
select throws_ok(
    $$select update_event_with_payments(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000010'::uuid,
        '{
            "name": "Protected Paid Event",
            "description": "Paid event used for purchased ticketing guard checks",
            "timezone": "UTC",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "kind_id": "virtual",
            "payment_currency_code": "USD",
            "ticket_types": [
                {
                    "active": true,
                    "event_ticket_type_id": "3a3c0000-0000-0000-0000-000000000036",
                    "order": 1,
                    "price_windows": [
                        {
                            "amount_minor": 2500,
                            "event_ticket_price_window_id": "3a3c0000-0000-0000-0000-000000000037"
                        }
                    ],
                    "seats_total": 0,
                    "title": "Protected General"
                },
                {
                    "active": true,
                    "event_ticket_type_id": "3a3c0000-0000-0000-0000-000000000038",
                    "order": 2,
                    "price_windows": [
                        {
                            "amount_minor": 5000,
                            "event_ticket_price_window_id": "3a3c0000-0000-0000-0000-000000000039"
                        }
                    ],
                    "seats_total": 5,
                    "title": "Protected VIP"
                }
            ]
        }'::jsonb
    )$$,
    'OCG01',
    'ticket type seats_total (0) cannot be less than current allocated seats (1)',
    'Should reject seat totals below the current purchased inventory for a ticket type'
);

-- Should throw error when purchased ticket types are removed
select throws_ok(
    $$select update_event_with_payments(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000010'::uuid,
        '{
            "name": "Protected Paid Event",
            "description": "Paid event used for purchased ticketing guard checks",
            "timezone": "UTC",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "kind_id": "virtual",
            "payment_currency_code": "USD",
            "ticket_types": [
                {
                    "active": true,
                    "event_ticket_type_id": "3a3c0000-0000-0000-0000-000000000038",
                    "order": 2,
                    "price_windows": [
                        {
                            "amount_minor": 5000,
                            "event_ticket_price_window_id": "3a3c0000-0000-0000-0000-000000000039"
                        }
                    ],
                    "seats_total": 5,
                    "title": "Protected VIP"
                }
            ]
        }'::jsonb
    )$$,
    'OCG01',
    'ticket types with purchases cannot be removed; deactivate them instead',
    'Should reject removing ticket types that already have purchases'
);

-- Should throw error when discount code total_available drops below redemptions
select throws_ok(
    $$select update_event_with_payments(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000010'::uuid,
        '{
            "name": "Protected Paid Event",
            "description": "Paid event used for purchased ticketing guard checks",
            "timezone": "UTC",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "discount_codes": [
                {
                    "active": true,
                    "amount_minor": 500,
                    "code": "PROTECT5",
                    "event_discount_code_id": "3a3c0000-0000-0000-0000-000000000040",
                    "kind": "fixed_amount",
                    "title": "Protected launch",
                    "total_available": 0
                }
            ],
            "kind_id": "virtual"
        }'::jsonb
    )$$,
    'OCG01',
    'discount code total_available cannot be less than existing redemptions',
    'Should reject lowering discount code availability below existing redemptions'
);

-- Should throw error when redeemed discount codes are removed
select throws_ok(
    $$select update_event_with_payments(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000010'::uuid,
        '{
            "name": "Protected Paid Event",
            "description": "Paid event used for purchased ticketing guard checks",
            "timezone": "UTC",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "discount_codes": [],
            "kind_id": "virtual"
        }'::jsonb
    )$$,
    'OCG01',
    'discount codes with redemptions cannot be removed; deactivate them instead',
    'Should reject removing discount codes that already have redemptions'
);

-- Should reconcile a public ticket queue after tier capacity increases
select lives_ok(
    format($$select update_event_with_payments(
        null::uuid,
        %L::uuid,
        %L::uuid,
        %L::jsonb
    )$$,
        :'group1ID',
        :'eventTicketQueueID',
        format(
            '{
                "name": "Ticket Queue Capacity Event",
                "description": "Published event for ticket queue capacity checks",
                "timezone": "UTC",
                "category_id": "%s",
                "kind_id": "in-person",
                "payment_currency_code": "USD",
                "starts_at": "2030-02-17T10:00:00",
                "ticket_types": [
                    {
                        "active": true,
                        "availability": "public",
                        "event_ticket_type_id": "%s",
                        "order": 1,
                        "price_windows": [
                            {
                                "amount_minor": 2500,
                                "event_ticket_price_window_id": "%s"
                            }
                        ],
                        "seats_total": 2,
                        "title": "Queue General"
                    }
                ],
                "venue_address": "123 Main St",
                "venue_city": "San Francisco",
                "venue_country_code": "US",
                "venue_name": "Community Hall",
                "venue_state_code": "CA",
                "venue_state_name": "California",
                "venue_zip_code": "94105"
            }',
            :'category1ID',
            :'ticketQueueTicketTypeID',
            :'ticketQueuePriceWindowID'
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
    $$
        select update_event_with_payments(
            '3a3c0000-0000-0000-0000-000000000024'::uuid,
            '3a3c0000-0000-0000-0000-000000000023'::uuid,
            '3a3c0000-0000-0000-0000-000000000016'::uuid,
            '{"name": "Draft Questions Event", "description": "Desc", "timezone": "UTC", "category_id": "3a3c0000-0000-0000-0000-000000000022", "kind_id": "in-person", "starts_at": "2030-01-01T10:00:00Z", "registration_questions": [{"id": "3a3c0000-0000-0000-0000-000000000031", "kind": "free-text", "prompt": "Original", "required": true, "options": []}]}'::jsonb
        )
    $$,
    'Should update registration questions while the event is unpublished'
);

-- Should store updated registration questions
select is(
    (
        select registration_questions
        from event
        where event_id = :'eventQuestionsID'::uuid
    ),
    '[{"id": "3a3c0000-0000-0000-0000-000000000031", "kind": "free-text", "prompt": "Original", "required": true, "options": []}]'::jsonb,
    'Should store updated registration questions'
);

-- Should validate registration questions when updating an event
select throws_ok(
    $$select update_event_with_payments(
        '3a3c0000-0000-0000-0000-000000000024'::uuid,
        '3a3c0000-0000-0000-0000-000000000023'::uuid,
        '3a3c0000-0000-0000-0000-000000000016'::uuid,
        '{"name": "Draft Questions Event", "description": "Desc", "timezone": "UTC", "category_id": "3a3c0000-0000-0000-0000-000000000022", "kind_id": "in-person", "starts_at": "2030-01-01T10:00:00Z", "registration_questions": [{"id": "bad", "kind": "free-text", "prompt": "Invalid", "required": true, "options": []}]}'::jsonb
    )$$,
    'OCG01',
    'questionnaire question id must be a uuid',
    'Should validate registration questions when updating an event'
);

-- Should update registration questions after publish when no answers exist
select lives_ok(
    $$select update_event_with_payments(
        '3a3c0000-0000-0000-0000-000000000024'::uuid,
        '3a3c0000-0000-0000-0000-000000000023'::uuid,
        '3a3c0000-0000-0000-0000-000000000017'::uuid,
        '{"name": "Published Questions Event", "description": "Desc", "timezone": "UTC", "category_id": "3a3c0000-0000-0000-0000-000000000022", "kind_id": "in-person", "starts_at": "2030-01-01T10:00:00Z", "registration_questions": [{"id": "3a3c0000-0000-0000-0000-000000000031", "kind": "free-text", "prompt": "Changed", "required": true, "options": []}]}'::jsonb
    )$$,
    'Should update registration questions after publish when no answers exist'
);

-- Should preserve registration questions when answers exist and questions are omitted
select lives_ok(
    $$select update_event_with_payments(
        '3a3c0000-0000-0000-0000-000000000024'::uuid,
        '3a3c0000-0000-0000-0000-000000000023'::uuid,
        '3a3c0000-0000-0000-0000-000000000015'::uuid,
        '{"name": "Answered Questions Event Updated", "description": "Desc", "timezone": "UTC", "category_id": "3a3c0000-0000-0000-0000-000000000022", "kind_id": "in-person", "starts_at": "2030-01-01T10:00:00Z"}'::jsonb
    )$$,
    'Should preserve registration questions when answers exist and questions are omitted'
);

-- Should reject registration question changes after answers exist
select throws_ok(
    $$select update_event_with_payments(
        '3a3c0000-0000-0000-0000-000000000024'::uuid,
        '3a3c0000-0000-0000-0000-000000000023'::uuid,
        '3a3c0000-0000-0000-0000-000000000015'::uuid,
        '{"name": "Answered Questions Event", "description": "Desc", "timezone": "UTC", "category_id": "3a3c0000-0000-0000-0000-000000000022", "kind_id": "in-person", "starts_at": "2030-01-01T10:00:00Z", "registration_questions": [{"id": "3a3c0000-0000-0000-0000-000000000031", "kind": "free-text", "prompt": "Changed", "required": true, "options": []}]}'::jsonb
    )$$,
    'OCG01',
    'registration questions cannot be changed after attendees have submitted answers',
    'Should reject registration question changes after answers exist'
);

-- Should allow unrelated event edits while checkout holds are active
select lives_ok(
    $$select update_event_with_payments(
        '3a3c0000-0000-0000-0000-000000000024'::uuid,
        '3a3c0000-0000-0000-0000-000000000023'::uuid,
        '3a3c0000-0000-0000-0000-000000000056'::uuid,
        '{"name": "Held Questions Event Updated", "description": "Desc", "timezone": "UTC", "category_id": "3a3c0000-0000-0000-0000-000000000022", "kind_id": "in-person", "starts_at": "2030-01-01T10:00:00Z", "venue_address": "123 Main St", "venue_city": "San Francisco", "venue_country_code": "US", "venue_name": "Community Hall", "venue_state_code": "CA", "venue_state_name": "California", "venue_zip_code": "94105"}'::jsonb
    )$$,
    'Should allow unrelated event edits while checkout holds are active'
);

-- Should reject registration question changes while checkout holds are active
select throws_ok(
    $$select update_event_with_payments(
        '3a3c0000-0000-0000-0000-000000000024'::uuid,
        '3a3c0000-0000-0000-0000-000000000023'::uuid,
        '3a3c0000-0000-0000-0000-000000000056'::uuid,
        '{"name": "Held Questions Event Updated", "description": "Desc", "timezone": "UTC", "category_id": "3a3c0000-0000-0000-0000-000000000022", "kind_id": "in-person", "starts_at": "2030-01-01T10:00:00Z", "registration_questions": [{"id": "3a3c0000-0000-0000-0000-000000000031", "kind": "free-text", "prompt": "Changed", "required": true, "options": []}]}'::jsonb
    )$$,
    'OCG01',
    'registration questions cannot be changed while checkout holds are active',
    'Should reject registration question changes while checkout holds are active'
);

-- Should clear payment-only configuration when the final positive price is removed
select lives_ok(
    $$select update_event_with_payments(
        null::uuid,
        '3a3c0000-0000-0000-0000-000000000018'::uuid,
        '3a3c0000-0000-0000-0000-000000000008'::uuid,
        '{
            "name": "Paid Event Updated",
            "description": "Event seeded for ticketing preservation tests",
            "timezone": "UTC",
            "category_id": "3a3c0000-0000-0000-0000-000000000001",
            "kind_id": "virtual",
            "discount_codes": null,
            "ticket_types": [
                {
                    "active": true,
                    "availability": "public",
                    "event_ticket_type_id": "3a3c0000-0000-0000-0000-000000000033",
                    "order": 1,
                    "price_windows": [
                        {
                            "amount_minor": 0,
                            "event_ticket_price_window_id": "3a3c0000-0000-0000-0000-000000000034"
                        }
                    ],
                    "seats_total": 10,
                    "title": "General"
                }
            ]
        }'::jsonb
    )$$,
    'Should clear payment-only configuration with the final positive price'
);

-- Should persist the provider-free configuration with its free ticket tier
select results_eq(
    $$
        select
            payment_currency_code,
            (select count(*)::int from event_discount_code where event_id = e.event_id),
            (select count(*)::int from event_ticket_type where event_id = e.event_id)
        from event e
        where event_id = '3a3c0000-0000-0000-0000-000000000008'::uuid
    $$,
    $$ values (null::text, 0::int, 1::int) $$,
    'Should persist provider-free configuration with its free ticket tier'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
