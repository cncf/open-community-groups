-- Tests releasing checkout-created attendee holds.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set activePurchaseID '79280000-0000-0000-0000-000000000009'
\set activeUserID '79280000-0000-0000-0000-000000000012'
\set communityID '79280000-0000-0000-0000-000000000001'
\set completedPurchaseID '79280000-0000-0000-0000-000000000010'
\set completedUserID '79280000-0000-0000-0000-000000000013'
\set eventCategoryID '79280000-0000-0000-0000-000000000002'
\set groupCategoryID '79280000-0000-0000-0000-000000000007'
\set groupID '79280000-0000-0000-0000-000000000008'
\set manualUserID '79280000-0000-0000-0000-000000000014'
\set priceWindowID '79280000-0000-0000-0000-000000000006'
\set releasedUserID '79280000-0000-0000-0000-000000000011'
\set eventID '79280000-0000-0000-0000-000000000003'
\set ticketTypeID '79280000-0000-0000-0000-000000000005'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories and users
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'activeUserID');
select fx_user(:'completedUserID');
select fx_user(:'manualUserID');
select fx_user(:'releasedUserID');

-- Group
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object('payment_recipient', jsonb_build_object(
        'provider', 'stripe',
        'recipient_id', 'acct_release_attendee_hold',
        'seller_display_name', 'Release Hold Fiscal Sponsor'
    )));

-- Events
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD',
    'published', true,
    'published_at', now(),
    'starts_at', now() + interval '1 day'
));

-- Ticket type
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General admission'
));

-- Price window
select fx_event_ticket_price_window(:'priceWindowID', :'ticketTypeID', jsonb_build_object('amount_minor', 2500));

-- Purchases that should protect their attendee rows
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    status,
    ticket_title,
    user_id
) values (
    :'activePurchaseID',
    0,
    'USD',
    0,
    :'eventID',
    :'ticketTypeID',
    now() + interval '10 minutes',
    'pending',
    'General admission',
    :'activeUserID'
), (
    :'completedPurchaseID',
    0,
    'USD',
    0,
    :'eventID',
    :'ticketTypeID',
    null,
    'completed',
    'General admission',
    :'completedUserID'
);

-- Pending attendee rows
insert into event_attendee (event_id, user_id, manually_invited, status)
values
    (:'eventID', :'releasedUserID', false, 'registration-questions-pending'),
    (:'eventID', :'activeUserID', false, 'registration-questions-pending'),
    (:'eventID', :'completedUserID', false, 'registration-questions-pending'),
    (:'eventID', :'manualUserID', true, 'registration-questions-pending');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should release a checkout-created pending attendee row without an active purchase
select lives_ok(
    format($$select release_event_checkout_attendee_hold(
        %L::uuid,
        %L::uuid
    )$$, :'eventID', :'releasedUserID'),
    'Should release a checkout-created pending attendee row without an active purchase'
);

-- Should remove the unprotected checkout-created attendee row
select is(
    (
        select count(*)::int
        from event_attendee
        where event_id = :'eventID'::uuid
        and user_id = :'releasedUserID'::uuid
    ),
    0,
    'Should remove the unprotected checkout-created attendee row'
);

-- Should leave protected pending attendee rows alone
select lives_ok(
    format($$
        select
            release_event_checkout_attendee_hold(
                %L::uuid,
                %L::uuid
            ),
            release_event_checkout_attendee_hold(
                %L::uuid,
                %L::uuid
            ),
            release_event_checkout_attendee_hold(
                %L::uuid,
                %L::uuid
            )
    $$, :'eventID', :'activeUserID', :'eventID', :'completedUserID', :'eventID', :'manualUserID'),
    'Should leave protected pending attendee rows alone'
);

-- Should preserve rows protected by active purchases or organizer invitations
select results_eq(
    format($$
        select
            (
                select count(*)::int
                from event_attendee
                where event_id = %L::uuid
                and user_id = %L::uuid
            ),
            (
                select count(*)::int
                from event_attendee
                where event_id = %L::uuid
                and user_id = %L::uuid
            ),
            (
                select count(*)::int
                from event_attendee
                where event_id = %L::uuid
                and user_id = %L::uuid
            )
    $$, :'eventID', :'activeUserID', :'eventID', :'completedUserID', :'eventID', :'manualUserID'),
    $$ values (1::int, 1::int, 1::int) $$,
    'Should preserve rows protected by active purchases or organizer invitations'
);

-- Should be idempotent for already released rows
select lives_ok(
    format($$select release_event_checkout_attendee_hold(
        %L::uuid,
        %L::uuid
    )$$, :'eventID', :'releasedUserID'),
    'Should be idempotent for already released rows'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
