-- Tests ending a user's active attendance at an event.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(18);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorUserID 'e3ac0000-0000-0000-0000-000000000001'
\set communityID 'e3ac0000-0000-0000-0000-000000000002'
\set completedReplacementPurchaseID 'e3ac0000-0000-0000-0000-000000000003'
\set completedReplacementRefundedPurchaseID 'e3ac0000-0000-0000-0000-000000000004'
\set completedReplacementUserID 'e3ac0000-0000-0000-0000-000000000005'
\set confirmedUserID 'e3ac0000-0000-0000-0000-000000000006'
\set eventCategoryID 'e3ac0000-0000-0000-0000-000000000007'
\set eventID 'e3ac0000-0000-0000-0000-000000000008'
\set groupCategoryID 'e3ac0000-0000-0000-0000-000000000009'
\set groupID 'e3ac0000-0000-0000-0000-000000000010'
\set invitationRefundedPurchaseID 'e3ac0000-0000-0000-0000-000000000011'
\set invitationUserID 'e3ac0000-0000-0000-0000-000000000012'
\set nullActorUserID 'e3ac0000-0000-0000-0000-000000000013'
\set questionsRefundedPurchaseID 'e3ac0000-0000-0000-0000-000000000014'
\set questionsRefundUserID 'e3ac0000-0000-0000-0000-000000000015'
\set questionsUserID 'e3ac0000-0000-0000-0000-000000000016'
\set refundPendingOtherPurchaseID 'e3ac0000-0000-0000-0000-000000000017'
\set refundPendingOtherRefundedPurchaseID 'e3ac0000-0000-0000-0000-000000000018'
\set refundPendingOtherUserID 'e3ac0000-0000-0000-0000-000000000019'
\set refundRequestedReplacementPurchaseID 'e3ac0000-0000-0000-0000-000000000020'
\set refundRequestedReplacementRefundedPurchaseID 'e3ac0000-0000-0000-0000-000000000021'
\set refundRequestedReplacementUserID 'e3ac0000-0000-0000-0000-000000000022'
\set selfRefundedPurchaseID 'e3ac0000-0000-0000-0000-000000000023'
\set selfRefundUserID 'e3ac0000-0000-0000-0000-000000000024'
\set ticketTypeID 'e3ac0000-0000-0000-0000-000000000025'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the event
select fx_community(:'communityID');

-- User recorded as the canceling actor
select fx_user(:'actorUserID');

-- User whose confirmed attendance is kept by a completed replacement purchase
select fx_user(:'completedReplacementUserID');

-- User whose checked-in confirmed attendance is ended without a refund
select fx_user(:'confirmedUserID');

-- User whose invitation-pending row is never ended
select fx_user(:'invitationUserID');

-- User whose confirmed attendance is ended without a canceling actor
select fx_user(:'nullActorUserID');

-- User whose checkout-answer attendance is ended by a refund
select fx_user(:'questionsRefundUserID');

-- User whose checkout-answer attendance is kept without a refund
select fx_user(:'questionsUserID');

-- User whose only other purchase is already awaiting its refund
select fx_user(:'refundPendingOtherUserID');

-- User whose confirmed attendance is kept by a refund-requested replacement purchase
select fx_user(:'refundRequestedReplacementUserID');

-- User whose refunded purchase is still refund-requested
select fx_user(:'selfRefundUserID');

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event whose attendance is ended
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD',
    'published', true,
    'published_at', now(),
    'starts_at', now() + interval '1 day'
));

-- Attendee rows covering every scenario
insert into event_attendee (
    checked_in,
    checked_in_at,
    event_id,
    manually_invited,
    status,
    user_id
) values
    (true, now() - interval '1 hour', :'eventID', false, 'confirmed', :'completedReplacementUserID'),
    (true, now() - interval '1 hour', :'eventID', false, 'confirmed', :'confirmedUserID'),
    (false, null, :'eventID', true, 'invitation-pending', :'invitationUserID'),
    (true, now() - interval '1 hour', :'eventID', false, 'confirmed', :'nullActorUserID'),
    (false, null, :'eventID', false, 'registration-questions-pending', :'questionsRefundUserID'),
    (false, null, :'eventID', false, 'registration-questions-pending', :'questionsUserID'),
    (true, now() - interval '1 hour', :'eventID', false, 'confirmed', :'refundPendingOtherUserID'),
    (true, now() - interval '1 hour', :'eventID', false, 'confirmed', :'refundRequestedReplacementUserID'),
    (true, now() - interval '1 hour', :'eventID', false, 'confirmed', :'selfRefundUserID');

-- Ticket type
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 20,
    'title', 'General admission'
));

-- Refunded purchases and the other purchases of the same users
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    refunded_at,
    status,
    ticket_title,
    user_id
) values
    (
        :'completedReplacementPurchaseID',
        0,
        'USD',
        0,
        :'eventID',
        :'ticketTypeID',
        null,
        'completed',
        'General admission',
        :'completedReplacementUserID'
    ),
    (
        :'completedReplacementRefundedPurchaseID',
        0,
        'USD',
        0,
        :'eventID',
        :'ticketTypeID',
        now(),
        'refunded',
        'General admission',
        :'completedReplacementUserID'
    ),
    (
        :'invitationRefundedPurchaseID',
        0,
        'USD',
        0,
        :'eventID',
        :'ticketTypeID',
        now(),
        'refunded',
        'General admission',
        :'invitationUserID'
    ),
    (
        :'questionsRefundedPurchaseID',
        0,
        'USD',
        0,
        :'eventID',
        :'ticketTypeID',
        now(),
        'refunded',
        'General admission',
        :'questionsRefundUserID'
    ),
    (
        :'refundPendingOtherPurchaseID',
        0,
        'USD',
        0,
        :'eventID',
        :'ticketTypeID',
        null,
        'refund-pending',
        'General admission',
        :'refundPendingOtherUserID'
    ),
    (
        :'refundPendingOtherRefundedPurchaseID',
        0,
        'USD',
        0,
        :'eventID',
        :'ticketTypeID',
        now(),
        'refunded',
        'General admission',
        :'refundPendingOtherUserID'
    ),
    (
        :'refundRequestedReplacementPurchaseID',
        0,
        'USD',
        0,
        :'eventID',
        :'ticketTypeID',
        null,
        'refund-requested',
        'General admission',
        :'refundRequestedReplacementUserID'
    ),
    (
        :'refundRequestedReplacementRefundedPurchaseID',
        0,
        'USD',
        0,
        :'eventID',
        :'ticketTypeID',
        now(),
        'refunded',
        'General admission',
        :'refundRequestedReplacementUserID'
    ),
    (
        :'selfRefundedPurchaseID',
        0,
        'USD',
        0,
        :'eventID',
        :'ticketTypeID',
        null,
        'refund-requested',
        'General admission',
        :'selfRefundUserID'
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should report ending attendance without a canceling actor
select is(
    mark_event_attendance_canceled(:'eventID', :'nullActorUserID', null),
    true,
    'Should report ending attendance without a canceling actor'
);

-- Should accept a null canceled-by user
select results_eq(
    format(
        $$
            select
                attendance_canceled_at,
                attendance_canceled_by_user_id,
                checked_in,
                checked_in_at,
                status
            from event_attendee
            where event_id = %L::uuid
            and user_id = %L::uuid
        $$,
        :'eventID',
        :'nullActorUserID'
    ),
    $$ values (current_timestamp, null::uuid, false, null::timestamptz, 'attendance-canceled'::text) $$,
    'Should accept a null canceled-by user'
);

-- Should report ending attendance when the only other purchase is refund-pending
select is(
    mark_event_attendance_canceled(
        :'eventID',
        :'refundPendingOtherUserID',
        :'actorUserID',
        :'refundPendingOtherRefundedPurchaseID'
    ),
    true,
    'Should report ending attendance when the only other purchase is refund-pending'
);

-- Should end attendance when the only other purchase is refund-pending
select results_eq(
    format(
        $$
            select
                attendance_canceled_at,
                attendance_canceled_by_user_id,
                checked_in,
                checked_in_at,
                status
            from event_attendee
            where event_id = %L::uuid
            and user_id = %L::uuid
        $$,
        :'eventID',
        :'refundPendingOtherUserID'
    ),
    format(
        $$ values (current_timestamp, %L::uuid, false, null::timestamptz, 'attendance-canceled'::text) $$,
        :'actorUserID'
    ),
    'Should end attendance when the only other purchase is refund-pending'
);

-- Should report ending confirmed attendance
select is(
    mark_event_attendance_canceled(:'eventID', :'confirmedUserID', :'actorUserID'),
    true,
    'Should report ending confirmed attendance'
);

-- Should end confirmed attendance with attribution and clear check-in
select results_eq(
    format(
        $$
            select
                attendance_canceled_at,
                attendance_canceled_by_user_id,
                checked_in,
                checked_in_at,
                status
            from event_attendee
            where event_id = %L::uuid
            and user_id = %L::uuid
        $$,
        :'eventID',
        :'confirmedUserID'
    ),
    format(
        $$ values (current_timestamp, %L::uuid, false, null::timestamptz, 'attendance-canceled'::text) $$,
        :'actorUserID'
    ),
    'Should end confirmed attendance with attribution and clear check-in'
);

-- Should report ending registration-questions-pending attendance when a refunded purchase is given
select is(
    mark_event_attendance_canceled(
        :'eventID',
        :'questionsRefundUserID',
        :'actorUserID',
        :'questionsRefundedPurchaseID'
    ),
    true,
    'Should report ending registration-questions-pending attendance when a refunded purchase is given'
);

-- Should end registration-questions-pending attendance when a refunded purchase is given
select results_eq(
    format(
        $$
            select
                attendance_canceled_at,
                attendance_canceled_by_user_id,
                checked_in,
                checked_in_at,
                status
            from event_attendee
            where event_id = %L::uuid
            and user_id = %L::uuid
        $$,
        :'eventID',
        :'questionsRefundUserID'
    ),
    format(
        $$ values (current_timestamp, %L::uuid, false, null::timestamptz, 'attendance-canceled'::text) $$,
        :'actorUserID'
    ),
    'Should end registration-questions-pending attendance when a refunded purchase is given'
);

-- Should report ending attendance whose refunded purchase is still refund-requested
select is(
    mark_event_attendance_canceled(
        :'eventID',
        :'selfRefundUserID',
        :'actorUserID',
        :'selfRefundedPurchaseID'
    ),
    true,
    'Should report ending attendance whose refunded purchase is still refund-requested'
);

-- Should ignore the refunded purchase itself when checking replacements
select results_eq(
    format(
        $$
            select
                attendance_canceled_at,
                attendance_canceled_by_user_id,
                checked_in,
                checked_in_at,
                status
            from event_attendee
            where event_id = %L::uuid
            and user_id = %L::uuid
        $$,
        :'eventID',
        :'selfRefundUserID'
    ),
    format(
        $$ values (current_timestamp, %L::uuid, false, null::timestamptz, 'attendance-canceled'::text) $$,
        :'actorUserID'
    ),
    'Should ignore the refunded purchase itself when checking replacements'
);

-- Should report keeping attendance when a completed replacement exists
select is(
    mark_event_attendance_canceled(
        :'eventID',
        :'completedReplacementUserID',
        :'actorUserID',
        :'completedReplacementRefundedPurchaseID'
    ),
    false,
    'Should report keeping attendance when a completed replacement exists'
);

-- Should keep attendance when a completed replacement exists
select results_eq(
    format(
        $$
            select
                attendance_canceled_at,
                attendance_canceled_by_user_id,
                checked_in,
                checked_in_at,
                status
            from event_attendee
            where event_id = %L::uuid
            and user_id = %L::uuid
        $$,
        :'eventID',
        :'completedReplacementUserID'
    ),
    $$ values (null::timestamptz, null::uuid, true, current_timestamp - interval '1 hour', 'confirmed'::text) $$,
    'Should keep attendance when a completed replacement exists'
);

-- Should report keeping attendance when a refund-requested replacement exists
select is(
    mark_event_attendance_canceled(
        :'eventID',
        :'refundRequestedReplacementUserID',
        :'actorUserID',
        :'refundRequestedReplacementRefundedPurchaseID'
    ),
    false,
    'Should report keeping attendance when a refund-requested replacement exists'
);

-- Should keep attendance when a refund-requested replacement exists
select results_eq(
    format(
        $$
            select
                attendance_canceled_at,
                attendance_canceled_by_user_id,
                checked_in,
                checked_in_at,
                status
            from event_attendee
            where event_id = %L::uuid
            and user_id = %L::uuid
        $$,
        :'eventID',
        :'refundRequestedReplacementUserID'
    ),
    $$ values (null::timestamptz, null::uuid, true, current_timestamp - interval '1 hour', 'confirmed'::text) $$,
    'Should keep attendance when a refund-requested replacement exists'
);

-- Should report keeping invitation-pending rows with and without a refunded purchase
select results_eq(
    format(
        $$
            select mark_event_attendance_canceled(%L::uuid, %L::uuid, %L::uuid, refunded_purchase_id)
            from unnest(array[null, %L::uuid]) with ordinality as p(refunded_purchase_id, position)
            order by position
        $$,
        :'eventID',
        :'invitationUserID',
        :'actorUserID',
        :'invitationRefundedPurchaseID'
    ),
    $$ values (false), (false) $$,
    'Should report keeping invitation-pending rows with and without a refunded purchase'
);

-- Should leave invitation-pending rows untouched
select results_eq(
    format(
        $$
            select
                attendance_canceled_at,
                attendance_canceled_by_user_id,
                checked_in,
                checked_in_at,
                status
            from event_attendee
            where event_id = %L::uuid
            and user_id = %L::uuid
        $$,
        :'eventID',
        :'invitationUserID'
    ),
    $$ values (null::timestamptz, null::uuid, false, null::timestamptz, 'invitation-pending'::text) $$,
    'Should leave invitation-pending rows untouched'
);

-- Should report keeping registration-questions-pending attendance without a refunded purchase
select is(
    mark_event_attendance_canceled(:'eventID', :'questionsUserID', :'actorUserID'),
    false,
    'Should report keeping registration-questions-pending attendance without a refunded purchase'
);

-- Should leave registration-questions-pending attendance unchanged without a refunded purchase
select results_eq(
    format(
        $$
            select
                attendance_canceled_at,
                attendance_canceled_by_user_id,
                checked_in,
                checked_in_at,
                status
            from event_attendee
            where event_id = %L::uuid
            and user_id = %L::uuid
        $$,
        :'eventID',
        :'questionsUserID'
    ),
    $$ values (null::timestamptz, null::uuid, false, null::timestamptz, 'registration-questions-pending'::text) $$,
    'Should leave registration-questions-pending attendance unchanged without a refunded purchase'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
