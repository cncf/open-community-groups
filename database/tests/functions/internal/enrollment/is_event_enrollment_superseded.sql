-- Tests whether a user's enrollment moved past a stale offer of a given source.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(10);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'f3070000-0000-0000-0000-000000000003'
\set equalOtherSourceOfferID 'f3070000-0000-0000-0000-000000000008'
\set equalOtherSourceUserID 'f3070000-0000-0000-0000-000000000009'
\set eventCategoryID 'f3070000-0000-0000-0000-00000000000a'
\set eventID 'f3070000-0000-0000-0000-00000000000b'
\set groupCategoryID 'f3070000-0000-0000-0000-00000000000e'
\set groupID 'f3070000-0000-0000-0000-00000000000f'
\set linkedCheckoutOfferID 'f3070000-0000-0000-0000-000000000015'
\set linkedPendingPurchaseID 'f3070000-0000-0000-0000-000000000016'
\set linkedPendingUserID 'f3070000-0000-0000-0000-000000000017'
\set newerCanceledOfferID 'f3070000-0000-0000-0000-00000000001a'
\set newerCanceledUserID 'f3070000-0000-0000-0000-00000000001b'
\set newerPendingOfferID 'f3070000-0000-0000-0000-00000000001c'
\set newerPendingUserID 'f3070000-0000-0000-0000-00000000001d'
\set newerSameSourceOfferID 'f3070000-0000-0000-0000-00000000001e'
\set newerSameSourceUserID 'f3070000-0000-0000-0000-00000000001f'
\set nullAnchorOfferID 'f3070000-0000-0000-0000-000000000020'
\set nullAnchorUserID 'f3070000-0000-0000-0000-000000000021'
\set olderOtherSourceOfferID 'f3070000-0000-0000-0000-000000000022'
\set olderOtherSourceUserID 'f3070000-0000-0000-0000-000000000023'
\set revivedAttendeeUserID 'f3070000-0000-0000-0000-000000000032'
\set strangerUserID 'f3070000-0000-0000-0000-000000000033'
\set ticketTypeID 'f3070000-0000-0000-0000-000000000034'
\set waitingUserID 'f3070000-0000-0000-0000-000000000035'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, group, event and ticket type
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_event(:'eventID', :'groupID', :'eventCategoryID');
select fx_event_ticket_type(:'ticketTypeID', :'eventID');

-- One user per scenario
select fx_user(:'equalOtherSourceUserID');
select fx_user(:'linkedPendingUserID');
select fx_user(:'newerCanceledUserID');
select fx_user(:'newerPendingUserID');
select fx_user(:'newerSameSourceUserID');
select fx_user(:'nullAnchorUserID');
select fx_user(:'olderOtherSourceUserID');
select fx_user(:'revivedAttendeeUserID');
select fx_user(:'strangerUserID');
select fx_user(:'waitingUserID');

-- Offers issued around the anchor: same source newer, other source older, equal and newer
insert into admission_offer (
    admission_offer_id,
    created_at,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    user_id
) values
    (:'newerSameSourceOfferID', '2024-01-02 00:00:00+00', :'eventID', :'ticketTypeID', '2024-01-03 00:00:00+00', 'waitlist', 'expired', :'newerSameSourceUserID'),
    (:'olderOtherSourceOfferID', '2023-12-31 00:00:00+00', :'eventID', :'ticketTypeID', '2024-01-01 00:00:00+00', 'organizer_invitation', 'expired', :'olderOtherSourceUserID'),
    (:'equalOtherSourceOfferID', '2024-01-01 00:00:00+00', :'eventID', :'ticketTypeID', '2024-01-02 00:00:00+00', 'organizer_invitation', 'expired', :'equalOtherSourceUserID'),
    (:'newerCanceledOfferID', '2024-01-02 00:00:00+00', :'eventID', :'ticketTypeID', '2024-01-03 00:00:00+00', 'organizer_invitation', 'canceled', :'newerCanceledUserID'),
    (:'newerPendingOfferID', '2024-01-02 00:00:00+00', :'eventID', :'ticketTypeID', '2099-01-01 00:00:00+00', 'organizer_invitation', 'pending', :'newerPendingUserID'),
    (:'nullAnchorOfferID', '2024-01-02 00:00:00+00', :'eventID', :'ticketTypeID', '2024-01-03 00:00:00+00', 'organizer_invitation', 'canceled', :'nullAnchorUserID');

-- Same-source offer claimed by the linked pending purchase
insert into admission_offer (
    admission_offer_id,
    amount_minor,
    created_at,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    ticket_title,
    user_id
) values
    (:'linkedCheckoutOfferID', 0, '2024-01-02 00:00:00+00', 0, :'eventID', :'ticketTypeID', '2099-01-01 00:00:00+00', 'waitlist', 'checkout_pending', 'General admission', :'linkedPendingUserID');

-- Revived attendee row older than the anchor
insert into event_attendee (created_at, event_id, status, user_id)
values ('2023-12-01 00:00:00+00', :'eventID', 'confirmed', :'revivedAttendeeUserID');

-- Pending purchase linked to the same-source offer it claims
insert into event_purchase (
    admission_offer_id,
    amount_minor,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    hold_expires_at,
    status,
    ticket_title,
    user_id
) values
    (:'linkedCheckoutOfferID', 0, 'USD', :'eventID', :'linkedPendingPurchaseID', :'ticketTypeID', current_timestamp + interval '10 minutes', 'pending', 'General admission', :'linkedPendingUserID');

-- Waiting-list entry that rejoined the queue
insert into event_waitlist (event_id, event_ticket_type_id, user_id)
values (:'eventID', :'ticketTypeID', :'waitingUserID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should ignore a newer offer from the same source
select is(
    is_event_enrollment_superseded(
        :'eventID'::uuid,
        :'newerSameSourceUserID'::uuid,
        'waitlist',
        '2024-01-01 00:00:00+00'::timestamptz
    ),
    false,
    'Should ignore a newer offer from the same source'
);

-- Should ignore an offer from another source issued at the anchor time
select is(
    is_event_enrollment_superseded(
        :'eventID'::uuid,
        :'equalOtherSourceUserID'::uuid,
        'waitlist',
        '2024-01-01 00:00:00+00'::timestamptz
    ),
    false,
    'Should ignore an offer from another source issued at the anchor time'
);

-- Should ignore an older offer from another source
select is(
    is_event_enrollment_superseded(
        :'eventID'::uuid,
        :'olderOtherSourceUserID'::uuid,
        'waitlist',
        '2024-01-01 00:00:00+00'::timestamptz
    ),
    false,
    'Should ignore an older offer from another source'
);

-- Should report a newer canceled offer from another source as superseding
select is(
    is_event_enrollment_superseded(
        :'eventID'::uuid,
        :'newerCanceledUserID'::uuid,
        'waitlist',
        '2024-01-01 00:00:00+00'::timestamptz
    ),
    true,
    'Should report a newer canceled offer from another source as superseding'
);

-- Should report a newer pending offer from another source as superseding
select is(
    is_event_enrollment_superseded(
        :'eventID'::uuid,
        :'newerPendingUserID'::uuid,
        'waitlist',
        '2024-01-01 00:00:00+00'::timestamptz
    ),
    true,
    'Should report a newer pending offer from another source as superseding'
);

-- Should report a pending purchase linked to a same-source offer as superseding
select is(
    is_event_enrollment_superseded(
        :'eventID'::uuid,
        :'linkedPendingUserID'::uuid,
        'waitlist',
        '2024-01-01 00:00:00+00'::timestamptz
    ),
    true,
    'Should report a pending purchase linked to a same-source offer as superseding'
);

-- Should report a revived attendee row older than the anchor as superseding
select is(
    is_event_enrollment_superseded(
        :'eventID'::uuid,
        :'revivedAttendeeUserID'::uuid,
        'waitlist',
        '2024-01-01 00:00:00+00'::timestamptz
    ),
    true,
    'Should report a revived attendee row older than the anchor as superseding'
);

-- Should report a user without other enrollment as not superseded
select is(
    is_event_enrollment_superseded(
        :'eventID'::uuid,
        :'strangerUserID'::uuid,
        'waitlist',
        '2024-01-01 00:00:00+00'::timestamptz
    ),
    false,
    'Should report a user without other enrollment as not superseded'
);

-- Should report a waiting-list entry as superseding
select is(
    is_event_enrollment_superseded(
        :'eventID'::uuid,
        :'waitingUserID'::uuid,
        'waitlist',
        '2024-01-01 00:00:00+00'::timestamptz
    ),
    true,
    'Should report a waiting-list entry as superseding'
);

-- Should skip offer recency when the anchor is null
select is(
    is_event_enrollment_superseded(
        :'eventID'::uuid,
        :'nullAnchorUserID'::uuid,
        'waitlist',
        null::timestamptz
    ),
    false,
    'Should skip offer recency when the anchor is null'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
