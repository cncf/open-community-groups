-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '79430000-0000-0000-0000-000000000001'
\set completedPurchaseID '79430000-0000-0000-0000-000000000002'
\set eventCategoryID '79430000-0000-0000-0000-000000000003'
\set eventID '79430000-0000-0000-0000-000000000004'
\set eventInactiveID '79430000-0000-0000-0000-000000000005'
\set eventInactiveTicketTypeID '79430000-0000-0000-0000-000000000006'
\set eventOpenUntilStartID '79430000-0000-0000-0000-000000000022'
\set eventOpenUntilStartTicketTypeID '79430000-0000-0000-0000-000000000023'
\set eventTicketTypeID '79430000-0000-0000-0000-000000000007'
\set expiredPurchaseID '79430000-0000-0000-0000-000000000008'
\set freePurchaseID '79430000-0000-0000-0000-000000000009'
\set groupCategoryID '79430000-0000-0000-0000-000000000010'
\set groupID '79430000-0000-0000-0000-000000000011'
\set inactivePurchaseID '79430000-0000-0000-0000-000000000012'
\set invitedPurchaseID '79430000-0000-0000-0000-000000000013'
\set openUntilStartPurchaseID '79430000-0000-0000-0000-000000000024'
\set paidPurchaseID '79430000-0000-0000-0000-000000000014'
\set priceWindowID '79430000-0000-0000-0000-000000000015'
\set registrationQuestionID '79430000-0000-0000-0000-000000000016'
\set user1ID '79430000-0000-0000-0000-000000000017'
\set user2ID '79430000-0000-0000-0000-000000000018'
\set user3ID '79430000-0000-0000-0000-000000000019'
\set user4ID '79430000-0000-0000-0000-000000000020'
\set user5ID '79430000-0000-0000-0000-000000000021'
\set user6ID '79430000-0000-0000-0000-000000000025'

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
    'free-community',
    'Free Community',
    'Test',
    'https://e/banner-mobile.png',
    'https://e/banner.png',
    'https://e/logo.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Tech');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'General');

-- Users
insert into "user" (user_id, auth_hash, email, email_verified, username)
values
    (
        :'user1ID',
        'hash-1',
        'user1@example.com',
        true,
        'user-1'
    ),
    (
        :'user2ID',
        'hash-2',
        'user2@example.com',
        true,
        'user-2'
    ),
    (
        :'user3ID',
        'hash-3',
        'user3@example.com',
        true,
        'user-3'
    ),
    (
        :'user4ID',
        'hash-4',
        'user4@example.com',
        true,
        'user-4'
    ),
    (
        :'user5ID',
        'hash-5',
        'user5@example.com',
        true,
        'user-5'
    ),
    (
        :'user6ID',
        'hash-6',
        'user6@example.com',
        true,
        'user-6'
    );

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Free Group', 'free-group');

-- Event
insert into event (
    event_id,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    ends_at,
    starts_at,
    published,
    published_at,
    registration_questions,
    registration_starts_at
) values (
    -- Event with pending registration answers created during checkout
    :'eventID',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Free Event',
    'free-event',
    'Test event',
    'UTC',
    null,
    now() + interval '1 day',
    true,
    now(),
    jsonb_build_array(jsonb_build_object(
        'id', :'registrationQuestionID',
        'kind', 'free-text',
        'options', jsonb_build_array(),
        'prompt', 'Note',
        'required', true
    )),
    null
), (
    :'eventInactiveID',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Inactive Free Event',
    'inactive-free-event',
    'Test event',
    'UTC',
    null,
    now() + interval '1 day',
    true,
    now(),
    '[]'::jsonb,
    null
), (
    :'eventOpenUntilStartID',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Open Until Start Free Event',
    'open-until-start-free-event',
    'Test event',
    'UTC',
    now() + interval '1 hour',
    now() - interval '1 hour',
    true,
    now(),
    '[]'::jsonb,
    now() - interval '2 hours'
);

-- Ticket type
insert into event_ticket_type (
    event_ticket_type_id,
    event_id,
    "order",
    seats_total,
    title
)
values
    (
        :'eventTicketTypeID',
        :'eventID',
        1,
        10,
        'General admission'
    ),
    (
        :'eventInactiveTicketTypeID',
        :'eventInactiveID',
        1,
        10,
        'General admission'
    ),
    (
        :'eventOpenUntilStartTicketTypeID',
        :'eventOpenUntilStartID',
        1,
        10,
        'General admission'
    );

-- Price window
insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values (
    :'priceWindowID',
    0,
    :'eventTicketTypeID'
);

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
    user_id
) values (
    :'freePurchaseID',
    0,
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    now() + interval '10 minutes',
    'pending',
    'General admission',
    :'user1ID'
), (
    :'expiredPurchaseID',
    0,
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    now() - interval '10 minutes',
    'pending',
    'General admission',
    :'user2ID'
), (
    :'inactivePurchaseID',
    0,
    'USD',
    :'eventInactiveID',
    :'eventInactiveTicketTypeID',
    now() + interval '10 minutes',
    'pending',
    'General admission',
    :'user2ID'
), (
    :'paidPurchaseID',
    2500,
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    now() + interval '10 minutes',
    'pending',
    'General admission',
    :'user3ID'
), (
    :'completedPurchaseID',
    0,
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    null,
    'completed',
    'General admission',
    :'user4ID'
), (
    :'invitedPurchaseID',
    0,
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    now() + interval '10 minutes',
    'pending',
    'General admission',
    :'user5ID'
), (
    :'openUntilStartPurchaseID',
    0,
    'USD',
    :'eventOpenUntilStartID',
    :'eventOpenUntilStartTicketTypeID',
    now() + interval '10 minutes',
    'pending',
    'General admission',
    :'user6ID'
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

-- Attendee with a pending invitation that checkout cannot confirm
insert into event_attendee (event_id, user_id, manually_invited, status)
values (
    :'eventID',
    :'user5ID',
    true,
    'invitation-pending'
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

-- Should reject expired purchase holds
select throws_ok(
    format($$select complete_free_event_purchase(%L::uuid)$$, :'expiredPurchaseID'),
    'purchase hold has expired',
    'Should reject expired purchase holds'
);

-- Should reject free purchases when the event becomes inactive
update event
set published = false
where event_id = :'eventInactiveID'::uuid;

select throws_ok(
    format($$select complete_free_event_purchase(%L::uuid)$$, :'inactivePurchaseID'),
    'event not found or inactive',
    'Should reject free purchases when the event becomes inactive'
);

-- Should complete active free holds after an open-only registration window reaches the event start
select is(
    complete_free_event_purchase(:'openUntilStartPurchaseID'::uuid)::jsonb,
    jsonb_build_object(
        'community_id', :'communityID'::uuid,
        'event_id', :'eventOpenUntilStartID'::uuid,
        'user_id', :'user6ID'::uuid
    ),
    'Should complete active free holds after an open-only registration window reaches the event start'
);

-- Should persist the open-only registration window free hold completion
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
                select status
                from event_attendee
                where event_id = ids.event_id
                and user_id = ids.user_id
            )
        from ids
    $$, :'openUntilStartPurchaseID', :'eventOpenUntilStartID', :'user6ID'),
    $$ values (true, true, 'completed'::text, 'confirmed'::text) $$,
    'Should persist the completed open-only free hold purchase and attendee row'
);

-- Should reject non-free purchases
select throws_ok(
    format($$select complete_free_event_purchase(%L::uuid)$$, :'paidPurchaseID'),
    'only free purchases can be completed locally',
    'Should reject non-free purchases'
);

-- Should reject purchases that are no longer pending
select throws_ok(
    format($$select complete_free_event_purchase(%L::uuid)$$, :'completedPurchaseID'),
    'purchase is no longer pending',
    'Should reject purchases that are no longer pending'
);

-- Should reject purchases whose attendee row cannot be confirmed
select throws_ok(
    format($$select complete_free_event_purchase(%L::uuid)$$, :'invitedPurchaseID'),
    'attendee cannot be confirmed for this event',
    'Should reject purchases whose attendee row cannot be confirmed'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
