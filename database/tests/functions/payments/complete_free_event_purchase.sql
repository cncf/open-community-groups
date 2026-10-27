-- Tests completing free event purchases.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '79430000-0000-0000-0000-000000000001'
\set completedPurchaseID '79430000-0000-0000-0000-000000000002'
\set eventCategoryID '79430000-0000-0000-0000-000000000003'
\set eventID '79430000-0000-0000-0000-000000000004'
\set eventInactiveID '79430000-0000-0000-0000-000000000005'
\set eventInactiveTicketTypeID '79430000-0000-0000-0000-000000000006'
\set eventTicketTypeID '79430000-0000-0000-0000-000000000007'
\set freePurchaseID '79430000-0000-0000-0000-000000000009'
\set groupCategoryID '79430000-0000-0000-0000-000000000010'
\set groupID '79430000-0000-0000-0000-000000000011'
\set inactivePurchaseID '79430000-0000-0000-0000-000000000012'
\set paidPurchaseID '79430000-0000-0000-0000-000000000014'
\set priceWindowID '79430000-0000-0000-0000-000000000015'
\set registrationQuestionID '79430000-0000-0000-0000-000000000016'
\set unknownPurchaseID '79430000-0000-0000-0000-000000000031'
\set user1ID '79430000-0000-0000-0000-000000000017'
\set user2ID '79430000-0000-0000-0000-000000000018'
\set user3ID '79430000-0000-0000-0000-000000000019'
\set user4ID '79430000-0000-0000-0000-000000000020'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, users and group
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'user1ID');
select fx_user(:'user2ID');
select fx_user(:'user3ID');
select fx_user(:'user4ID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event with pending registration answers created during checkout
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'published_at', now(),
    'registration_questions', jsonb_build_array(jsonb_build_object(
        'id', :'registrationQuestionID',
        'kind', 'free-text',
        'options', jsonb_build_array(),
        'prompt', 'Note',
        'required', true
    )),
    'starts_at', now() + interval '1 day'
));

-- Unpublished event
select fx_event(:'eventInactiveID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'starts_at', now() + interval '1 day'
));

-- Ticket types
select fx_event_ticket_type(:'eventTicketTypeID', :'eventID', jsonb_build_object('seats_total', 10));
select fx_event_ticket_type(:'eventInactiveTicketTypeID', :'eventInactiveID', jsonb_build_object('seats_total', 10));

-- Price window
select fx_event_ticket_price_window(:'priceWindowID', :'eventTicketTypeID', jsonb_build_object('amount_minor', 0));

-- Purchases
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    currency_code,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    status,
    ticket_title,
    user_id,

    admission_offer_id
) values (
    :'freePurchaseID',
    0,
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    now() + interval '10 minutes',
    'pending',
    'General admission',
    :'user1ID',
    null
), (
    :'inactivePurchaseID',
    0,
    'USD',
    :'eventInactiveID',
    :'eventInactiveTicketTypeID',
    now() + interval '10 minutes',
    'pending',
    'General admission',
    :'user2ID',
    null
), (
    :'completedPurchaseID',
    0,
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    null,
    'completed',
    'General admission',
    :'user4ID',
    null
);

-- Paid direct charge used to verify the free-completion boundary
insert into event_purchase (
    amount_minor,
    charge_model,
    connected_seller_id,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    hold_expires_at,
    payment_provider_id,
    provider_object_account_id,
    seller_snapshot,
    status,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    ticket_title,
    user_id,
    venue_snapshot
) values (
    2500,
    'direct-charge',
    'acct_free_boundary',
    'USD',
    :'eventID',
    :'paidPurchaseID',
    :'eventTicketTypeID',
    now() + interval '10 minutes',
    'stripe',
    'acct_free_boundary',
    '{"connected_account_id":"acct_free_boundary","display_name":"Sponsor","provider":"stripe"}'::jsonb,
    'pending',
    'inclusive',
    'manual',
    'professional-event-admission',
    'General admission',
    :'user3ID',
    '{}'::jsonb
);

-- Pending attendee row with registration answers created during checkout
insert into event_attendee (event_id, user_id, registration_answers, status)
values (
    :'eventID',
    :'user1ID',
    jsonb_build_object(
        'answers',
        jsonb_build_array(jsonb_build_object(
            'question_id', :'registrationQuestionID',
            'value', 'Free checkout answer'
        ))
    ),
    'registration-questions-pending'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should complete a pending free purchase
select is(
    complete_free_event_purchase(:'freePurchaseID'::uuid)::jsonb,
    jsonb_build_object(
        'community_id', :'communityID'::uuid,
        'event_id', :'eventID'::uuid,
        'user_id', :'user1ID'::uuid
    ),
    'Should complete a pending free purchase'
);

-- Should persist the completed purchase fields and add the attendee
select results_eq(
    format($$
        with ids as (
            select
                %L::uuid as event_purchase_id,
                %L::uuid as event_id,
                %L::uuid as user_id
        )
        select
            (
                select completed_at is not null
                from event_purchase
                where event_purchase_id = ids.event_purchase_id
            ),
            (
                select hold_expires_at is null
                from event_purchase
                where event_purchase_id = ids.event_purchase_id
            ),
            (
                select status
                from event_purchase
                where event_purchase_id = ids.event_purchase_id
            ),
            (
                select count(*)::int
                from event_attendee
                where event_id = ids.event_id
                and user_id = ids.user_id
            ),
            (
                select manually_invited
                from event_attendee
                where event_id = ids.event_id
                and user_id = ids.user_id
            ),
            (
                select status
                from event_attendee
                where event_id = ids.event_id
                and user_id = ids.user_id
            ),
            (
                select registration_answers
                from event_attendee
                where event_id = ids.event_id
                and user_id = ids.user_id
            )
        from ids
    $$, :'freePurchaseID', :'eventID', :'user1ID'),
    format($$
        values (
            true,
            true,
            'completed'::text,
            1::int,
            false,
            'confirmed'::text,
            '{"answers": [{"question_id": "%s", "value": "Free checkout answer"}]}'::jsonb
        )
    $$, :'registrationQuestionID'),
    'Should persist the completed purchase fields and confirm a non-manually invited attendee'
);

-- Should reject free purchases when the event is inactive
select throws_ok(
    format($$select complete_free_event_purchase(%L::uuid)$$, :'inactivePurchaseID'),
    'OCG01',
    'event not found or inactive',
    'Should reject free purchases when the event is inactive'
);

-- Should reject non-free purchases
select throws_ok(
    format($$select complete_free_event_purchase(%L::uuid)$$, :'paidPurchaseID'),
    'OCG01',
    'only free purchases can be completed locally',
    'Should reject non-free purchases'
);

-- Should reject purchases that are no longer pending
select throws_ok(
    format($$select complete_free_event_purchase(%L::uuid)$$, :'completedPurchaseID'),
    'OCG01',
    'purchase is no longer pending',
    'Should reject purchases that are no longer pending'
);

-- Should reject unknown purchases
select throws_ok(
    format($$select complete_free_event_purchase(%L::uuid)$$, :'unknownPurchaseID'),
    'OCG01',
    'purchase not found',
    'Should reject unknown purchases'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
