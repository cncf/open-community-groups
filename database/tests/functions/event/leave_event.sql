-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(27);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '5e090000-0000-0000-0000-000000000001'
\set eventApprovalPending '5e090000-0000-0000-0000-000000000002'
\set eventCanceled '5e090000-0000-0000-0000-000000000003'
\set eventCategoryID '5e090000-0000-0000-0000-000000000004'
\set eventDeleted '5e090000-0000-0000-0000-000000000005'
\set eventDisabledWaitlist '5e090000-0000-0000-0000-000000000006'
\set eventFull '5e090000-0000-0000-0000-000000000007'
\set eventInactiveGroup '5e090000-0000-0000-0000-000000000008'
\set eventOK '5e090000-0000-0000-0000-000000000009'
\set eventPaidTicketed '5e090000-0000-0000-0000-00000000000a'
\set eventPaidTicketedPurchaseID '5e090000-0000-0000-0000-00000000000b'
\set eventPaidTicketTypeID '5e090000-0000-0000-0000-00000000000c'
\set eventPast '5e090000-0000-0000-0000-00000000000d'
\set eventQuestionsInvited '5e090000-0000-0000-0000-00000000000e'
\set eventQuestionsPromoted '5e090000-0000-0000-0000-00000000000f'
\set eventStartedNoEnd '5e090000-0000-0000-0000-000000000010'
\set eventTicketed '5e090000-0000-0000-0000-000000000011'
\set eventTicketedDiscountCodeID '5e090000-0000-0000-0000-000000000012'
\set eventTicketedPurchaseID '5e090000-0000-0000-0000-000000000013'
\set eventTicketTypeID '5e090000-0000-0000-0000-000000000014'
\set eventUnlimited '5e090000-0000-0000-0000-000000000015'
\set eventUnpublished '5e090000-0000-0000-0000-000000000016'
\set eventWaitlist '5e090000-0000-0000-0000-000000000017'
\set groupCategoryID '5e090000-0000-0000-0000-000000000018'
\set groupID '5e090000-0000-0000-0000-000000000019'
\set inactiveGroupID '5e090000-0000-0000-0000-00000000001a'
\set questionID '5e090000-0000-0000-0000-00000000001b'
\set user1ID '5e090000-0000-0000-0000-00000000001c'
\set user2ID '5e090000-0000-0000-0000-00000000001d'
\set user3ID '5e090000-0000-0000-0000-00000000001e'
\set user4ID '5e090000-0000-0000-0000-00000000001f'
\set user5ID '5e090000-0000-0000-0000-000000000020'
\set user6ID '5e090000-0000-0000-0000-000000000021'

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
    'test-community',
    'Test Community',
    'A test community',
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
insert into "user" (user_id, auth_hash, email, email_verified, username)
values
    (:'user1ID', 'user-1-hash', 'u1@test.com', true, 'u1'),
    (:'user2ID', 'user-2-hash', 'u2@test.com', true, 'u2'),
    (:'user3ID', 'user-3-hash', 'u3@test.com', true, 'u3'),
    (:'user4ID', 'user-4-hash', 'u4@test.com', true, 'u4'),
    (:'user5ID', 'user-5-hash', 'u5@test.com', true, 'u5'),
    (:'user6ID', 'user-6-hash', 'u6@test.com', true, 'u6');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug, active, deleted)
values
    (:'groupID', :'communityID', :'groupCategoryID', 'Active Group', 'active-group', true, false),
    (
        :'inactiveGroupID',
        :'communityID',
        :'groupCategoryID',
        'Inactive Group',
        'inactive-group',
        false,
        false
    );

-- Events
insert into event (
    event_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    group_id,
    attendee_approval_required,
    published,
    canceled,
    deleted,
    starts_at,
    ends_at,
    capacity,
    waitlist_enabled
)
values
    (
        :'eventOK',
        'OK',
        'ok',
        'Test event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        false,
        true,
        false,
        false,
        null,
        null,
        null,
        false
    ),
    (
        :'eventApprovalPending',
        'Approval Pending',
        'approval-pending',
        'Test event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        true,
        true,
        false,
        false,
        null,
        null,
        null,
        false
    ),
    (
        :'eventCanceled',
        'Canceled',
        'canceled',
        'Test event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        false,
        false,
        true,
        false,
        null,
        null,
        1,
        true
    ),
    (
        :'eventDeleted',
        'Deleted',
        'deleted',
        'Test event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        false,
        false,
        false,
        true,
        null,
        null,
        null,
        false
    ),
    (
        :'eventInactiveGroup',
        'Inactive Group',
        'inactive-group',
        'Test event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'inactiveGroupID',
        false,
        true,
        false,
        false,
        null,
        null,
        null,
        false
    ),
    (
        :'eventUnpublished',
        'Unpublished',
        'unpublished',
        'Test event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        false,
        false,
        false,
        false,
        null,
        null,
        null,
        false
    ),
    (
        :'eventPast',
        'Past',
        'past',
        'Test event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        false,
        true,
        false,
        false,
        current_timestamp - interval '2 hours',
        current_timestamp - interval '1 hour',
        null,
        false
    ),
    (
        :'eventStartedNoEnd',
        'Started No End',
        'started-no-end',
        'Test event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        false,
        true,
        false,
        false,
        current_timestamp - interval '1 hour',
        null,
        null,
        false
    ),
    (
        :'eventDisabledWaitlist',
        'Disabled Waitlist',
        'disabled-waitlist',
        'Test event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        false,
        true,
        false,
        false,
        null,
        null,
        2,
        false
    ),
    (
        :'eventFull',
        'Full',
        'full',
        'Test event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        false,
        true,
        false,
        false,
        null,
        null,
        1,
        true
    ),
    (
        :'eventPaidTicketed',
        'Paid Ticketed',
        'paid-ticketed',
        'Test event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        false,
        true,
        false,
        false,
        null,
        null,
        1,
        false
    ),
    (
        :'eventUnlimited',
        'Unlimited',
        'unlimited',
        'Test event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        false,
        true,
        false,
        false,
        null,
        null,
        null,
        false
    ),
    (
        :'eventWaitlist',
        'Waitlist',
        'waitlist',
        'Test event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        false,
        true,
        false,
        false,
        null,
        null,
        1,
        true
    );

-- Event
insert into event (
    event_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    group_id,
    payment_currency_code,
    published,
    canceled,
    deleted,
    starts_at,
    ends_at,
    capacity,
    waitlist_enabled
) values (
    :'eventTicketed',
    'Ticketed',
    'ticketed',
    'd',
    'UTC',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'USD',
    true,
    false,
    false,
    null,
    null,
    1,
    false
);

-- Events with registration questions used to release pending-question seats
insert into event (
    event_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    group_id,
    published,
    canceled,
    deleted,
    starts_at,
    ends_at,
    capacity,
    waitlist_enabled,
    registration_questions
) values
    (
        :'eventQuestionsPromoted',
        'Questions Promoted',
        'questions-promoted',
        'd',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        true,
        false,
        false,
        null,
        null,
        1,
        true,
        format(
            '[{"id": "%s", "kind": "free-text", "prompt": "Note", "required": true, "options": []}]',
            :'questionID'
        )::jsonb
    ),
    (
        :'eventQuestionsInvited',
        'Questions Invited',
        'questions-invited',
        'd',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        true,
        false,
        false,
        null,
        null,
        1,
        true,
        format(
            '[{"id": "%s", "kind": "free-text", "prompt": "Note", "required": true, "options": []}]',
            :'questionID'
        )::jsonb
    );

-- Event Ticket Type
insert into event_ticket_type (
    event_ticket_type_id,
    event_id,
    "order",
    seats_total,
    title
) values (
    :'eventTicketTypeID',
    :'eventTicketed',
    1,
    1,
    'General admission'
);

-- Event Ticket Type
insert into event_ticket_type (
    event_ticket_type_id,
    event_id,
    "order",
    seats_total,
    title
) values (
    :'eventPaidTicketTypeID',
    :'eventPaidTicketed',
    1,
    1,
    'Paid admission'
);

-- Event Discount Code
insert into event_discount_code (
    event_discount_code_id,
    amount_minor,
    available,
    available_override_active,
    code,
    event_id,
    kind,
    title
) values (
    :'eventTicketedDiscountCodeID',
    1,
    0,
    true,
    'FREEPASS',
    :'eventTicketed',
    'fixed_amount',
    'Free pass'
);

-- Event Attendees
insert into event_attendee (event_id, user_id, status) values
    (:'eventOK', :'user1ID', 'confirmed'),
    (:'eventOK', :'user3ID', 'invitation-pending'),
    (:'eventDisabledWaitlist', :'user1ID', 'confirmed'),
    (:'eventDisabledWaitlist', :'user2ID', 'confirmed'),
    (:'eventPast', :'user1ID', 'confirmed'),
    (:'eventPaidTicketed', :'user3ID', 'confirmed'),
    (:'eventQuestionsPromoted', :'user5ID', 'registration-questions-pending'),
    (:'eventStartedNoEnd', :'user1ID', 'confirmed'),
    (:'eventFull', :'user1ID', 'confirmed'),
    (:'eventUnlimited', :'user1ID', 'confirmed'),
    (:'eventTicketed', :'user1ID', 'confirmed'),
    (:'eventTicketed', :'user5ID', 'registration-questions-pending');

-- Manually invited attendee pending registration answers
insert into event_attendee (event_id, user_id, manually_invited, status)
values (:'eventQuestionsInvited', :'user5ID', true, 'registration-questions-pending');

-- Event Waitlists
insert into event_waitlist (event_id, user_id, created_at) values
    (:'eventCanceled', :'user4ID', current_timestamp),
    (:'eventDisabledWaitlist', :'user3ID', current_timestamp),
    (:'eventFull', :'user2ID', current_timestamp),
    (:'eventFull', :'user3ID', current_timestamp + interval '1 minute'),
    (:'eventQuestionsInvited', :'user6ID', current_timestamp),
    (:'eventQuestionsPromoted', :'user6ID', current_timestamp),
    (:'eventTicketed', :'user2ID', current_timestamp + interval '30 seconds'),
    (:'eventUnlimited', :'user2ID', current_timestamp),
    (:'eventUnlimited', :'user4ID', current_timestamp + interval '1 minute'),
    (:'eventWaitlist', :'user2ID', current_timestamp);

-- Event Invitation Requests
insert into event_invitation_request (event_id, user_id, status)
values (:'eventApprovalPending', :'user4ID', 'pending');

-- Event Purchase
insert into event_purchase (
    event_purchase_id,
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
    :'eventTicketedPurchaseID',
    0,
    'USD',
    'FREEPASS',
    :'eventTicketedDiscountCodeID',
    :'eventTicketed',
    :'eventTicketTypeID',
    'completed',
    'General admission',
    :'user1ID'
);

-- Event Purchase
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    currency_code,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id
) values (
    :'eventPaidTicketedPurchaseID',
    1500,
    'USD',
    :'eventPaidTicketed',
    :'eventPaidTicketTypeID',
    'completed',
    'Paid admission',
    :'user3ID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should remove an attendee from a normal event
select is(
    leave_event(:'communityID'::uuid, :'eventOK'::uuid, :'user1ID'::uuid)::jsonb,
    '{"left_status":"attendee","promoted_user_ids":[]}'::jsonb,
    'Removes attendee and returns attendee leave payload'
);

-- Should preserve inactive attendee history after leaving
select results_eq(
    format($$
        select
            attendance_canceled_at is not null,
            attendance_canceled_by_user_id,
            status
        from event_attendee
        where event_id = %L::uuid and user_id = %L::uuid
    $$, :'eventOK', :'user1ID'),
    format($$ values (true, %L::uuid, 'attendance-canceled'::text) $$, :'user1ID'),
    'Preserves inactive attendee history after leaving'
);

-- Should allow a user to leave the waitlist
select is(
    leave_event(:'communityID'::uuid, :'eventWaitlist'::uuid, :'user2ID'::uuid)::jsonb,
    '{"left_status":"waitlisted","promoted_user_ids":[]}'::jsonb,
    'Removes waitlisted user and returns waitlisted leave payload'
);

-- Should remove waitlist row after leaving the waitlist
select ok(
    not exists(
        select 1
        from event_waitlist
        where event_id = :'eventWaitlist'::uuid and user_id = :'user2ID'::uuid
    ),
    'Deletes waitlist row after leaving the waitlist'
);

-- Should allow a user to leave a pending invitation request
select is(
    leave_event(:'communityID'::uuid, :'eventApprovalPending'::uuid, :'user4ID'::uuid)::jsonb,
    '{"left_status":"pending-approval","promoted_user_ids":[]}'::jsonb,
    'Removes pending invitation request and returns pending-approval leave payload'
);

-- Should remove pending invitation request row after leaving
select ok(
    not exists(
        select 1
        from event_invitation_request
        where event_id = :'eventApprovalPending'::uuid and user_id = :'user4ID'::uuid
    ),
    'Deletes pending invitation request row after leaving'
);

-- Should promote the next waitlisted user when a confirmed attendee leaves a full event
select is(
    leave_event(:'communityID'::uuid, :'eventFull'::uuid, :'user1ID'::uuid)::jsonb,
    format('{"left_status":"attendee","promoted_user_ids":["%s"]}', :'user2ID')::jsonb,
    'Promotes the oldest waitlisted user when capacity opens'
);

-- Should reject paid attendees trying to leave a ticketed event
select throws_ok(
    format(
        'select leave_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventPaidTicketed', :'user3ID'
    ),
    'paid attendees must request a refund instead of leaving the event',
    'Should reject paid attendees trying to leave a ticketed event'
);

-- Should keep paid attendees and purchases unchanged after rejection
select is(
    (
        select jsonb_build_object(
            'attending', exists(
                select 1
                from event_attendee
                where event_id = :'eventPaidTicketed'::uuid
                and user_id = :'user3ID'::uuid
            ),
            'purchase_status', (
                select status
                from event_purchase
                where event_purchase_id = :'eventPaidTicketedPurchaseID'::uuid
            )
        )
    ),
    '{"attending": true, "purchase_status": "completed"}'::jsonb,
    'Should keep paid attendees and purchases unchanged after rejection'
);

-- Should move the promoted user into attendees and remove them from the waitlist
select is(
    (
        select jsonb_build_object(
            'attendees', (
                select jsonb_agg(user_id order by user_id)
                from event_attendee
                where event_id = :'eventFull'::uuid
            ),
            'waitlist', (
                select jsonb_agg(user_id order by user_id)
                from event_waitlist
                where event_id = :'eventFull'::uuid
            )
        )
    ),
    format(
        '{"attendees":["%s","%s"],"waitlist":["%s"]}',
        :'user1ID',
        :'user2ID',
        :'user3ID'
    )::jsonb,
    'Preserves the canceled attendee and moves the promoted user into attendees'
);

-- Should continue promoting existing waitlisted users after waitlist is disabled
select is(
    leave_event(:'communityID'::uuid, :'eventDisabledWaitlist'::uuid, :'user1ID'::uuid)::jsonb,
    format('{"left_status":"attendee","promoted_user_ids":["%s"]}', :'user3ID')::jsonb,
    'Promotes existing waitlisted users even after waitlist is disabled'
);

-- Should promote the full remaining queue when an unlimited event loses an attendee
select is(
    leave_event(:'communityID'::uuid, :'eventUnlimited'::uuid, :'user1ID'::uuid)::jsonb,
    format(
        '{"left_status":"attendee","promoted_user_ids":["%s","%s"]}',
        :'user2ID',
        :'user4ID'
    )::jsonb,
    'Promotes all waitlisted users when the event capacity is unlimited'
);

-- Should not promote waitlisted users when leaving a ticketed event
select is(
    leave_event(:'communityID'::uuid, :'eventTicketed'::uuid, :'user1ID'::uuid)::jsonb,
    '{"left_status":"attendee","promoted_user_ids":[]}'::jsonb,
    'Should not promote waitlisted users when a ticketed attendee leaves'
);

-- Should keep queued ticketed users waitlisted after an attendee leaves
select is(
    (
        select jsonb_build_object(
            'purchase_status', (
                select status
                from event_purchase
                where event_purchase_id = :'eventTicketedPurchaseID'::uuid
            ),
            'waitlist', (
                select jsonb_agg(user_id order by user_id)
                from event_waitlist
                where event_id = :'eventTicketed'::uuid
            )
        )
    ),
    format(
        '{"purchase_status":"refunded","waitlist":["%s"]}',
        :'user2ID'
    )::jsonb,
    'Should keep queued ticketed users waitlisted after an attendee leaves'
);

-- Should restore the discount code remaining uses when a free ticketed attendee leaves
select is(
    (
        select available
        from event_discount_code
        where event_discount_code_id = :'eventTicketedDiscountCodeID'::uuid
    ),
    1,
    'Should restore the discount code remaining uses when a free ticketed attendee leaves'
);

-- Should move all waitlisted users into attendees for unlimited-capacity events
select is(
    (
        select jsonb_build_object(
            'attendees', (
                select jsonb_agg(user_id order by user_id)
                from event_attendee
                where event_id = :'eventUnlimited'::uuid
            ),
            'waitlist', (
                select coalesce(jsonb_agg(user_id order by user_id), '[]'::jsonb)
                from event_waitlist
                where event_id = :'eventUnlimited'::uuid
            )
        )
    ),
    format(
        '{"attendees":["%s","%s","%s"],"waitlist":[]}',
        :'user1ID',
        :'user2ID',
        :'user4ID'
    )::jsonb,
    'Preserves the canceled attendee and moves the full waitlist into attendees'
);

-- Should release a promoted pending-questions registration and promote the next user
select is(
    leave_event(:'communityID'::uuid, :'eventQuestionsPromoted'::uuid, :'user5ID'::uuid)::jsonb,
    format('{"left_status":"attendee","promoted_user_ids":["%s"]}', :'user6ID')::jsonb,
    'Releases a promoted pending-questions registration and promotes the next user'
);

-- Should delete the promoted pending-questions row and queue the next user for answers
select is(
    (
        select jsonb_agg(jsonb_build_array(user_id, status) order by user_id)
        from event_attendee
        where event_id = :'eventQuestionsPromoted'::uuid
    ),
    format(
        '[["%s","attendance-canceled"],["%s","registration-questions-pending"]]',
        :'user5ID',
        :'user6ID'
    )::jsonb,
    'Preserves the canceled pending-questions row and queues the next user for answers'
);

-- Should turn a manually invited pending-questions registration into a rejected invitation
select is(
    leave_event(:'communityID'::uuid, :'eventQuestionsInvited'::uuid, :'user5ID'::uuid)::jsonb,
    format('{"left_status":"attendee","promoted_user_ids":["%s"]}', :'user6ID')::jsonb,
    'Releases a manually invited pending-questions registration and promotes the next user'
);

-- Should keep the rejected manual invitation on record after leaving
select is(
    (
        select jsonb_build_array(manually_invited, status)
        from event_attendee
        where event_id = :'eventQuestionsInvited'::uuid
        and user_id = :'user5ID'::uuid
    ),
    '[true, "invitation-rejected"]'::jsonb,
    'Keeps the rejected manual invitation on record after leaving'
);

-- Should not release pending-questions registrations on ticketed events
select throws_ok(
    format(
        'select leave_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventTicketed', :'user5ID'
    ),
    'user is not attending or waitlisted for this event',
    'Does not release pending-questions registrations on ticketed events'
);

-- Should reject pending organizer-created invitations
select throws_ok(
    format(
        'select leave_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventOK', :'user3ID'
    ),
    'user is not attending or waitlisted for this event',
    'Rejects leave requests for pending organizer-created invitations'
);

-- Should reject past events
select throws_ok(
    format(
        'select leave_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventPast', :'user1ID'
    ),
    'event not found or inactive',
    'Rejects leave requests for past events'
);

-- Should reject started events without an end time
select throws_ok(
    format(
        'select leave_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventStartedNoEnd', :'user1ID'
    ),
    'event not found or inactive',
    'Rejects started events without an end time for leave requests'
);

-- Should reject waitlist leave requests for canceled events
select throws_ok(
    format(
        'select leave_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventCanceled', :'user4ID'
    ),
    'event not found or inactive',
    'Rejects waitlist leave requests for canceled events'
);

-- Should reject deleted events
select throws_ok(
    format(
        'select leave_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventDeleted', :'user1ID'
    ),
    'event not found or inactive',
    'Rejects leave requests for deleted events'
);

-- Should reject events from inactive groups
select throws_ok(
    format(
        'select leave_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventInactiveGroup', :'user1ID'
    ),
    'event not found or inactive',
    'Rejects leave requests for inactive-group events'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
