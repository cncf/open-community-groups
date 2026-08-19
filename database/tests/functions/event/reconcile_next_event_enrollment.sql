-- Tests claiming the next event that requires enrollment reconciliation.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(10);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '4a170000-0000-0000-0000-000000000001'
\set dueOfferID '4a170000-0000-0000-0000-000000000002'
\set eventCategoryID '4a170000-0000-0000-0000-000000000003'
\set eventID '4a170000-0000-0000-0000-000000000004'
\set futureOfferID '4a170000-0000-0000-0000-000000000005'
\set futureRecipientID '4a170000-0000-0000-0000-000000000006'
\set groupCategoryID '4a170000-0000-0000-0000-000000000007'
\set groupID '4a170000-0000-0000-0000-000000000008'
\set priceWindowID '4a170000-0000-0000-0000-00000000000b'
\set queueRecipientID '4a170000-0000-0000-0000-00000000000c'
\set recipientID '4a170000-0000-0000-0000-000000000009'
\set rsvpDueOfferID '4a170000-0000-0000-0000-00000000000d'
\set rsvpEventID '4a170000-0000-0000-0000-00000000000e'
\set rsvpQueueRecipientID '4a170000-0000-0000-0000-00000000000f'
\set rsvpRecipientID '4a170000-0000-0000-0000-000000000010'
\set ticketTypeID '4a170000-0000-0000-0000-00000000000a'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community hosting the reconciliation worker scenarios
insert into community (
    banner_mobile_url,
    banner_url,
    community_id,
    description,
    display_name,
    logo_url,
    name
) values (
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    :'communityID',
    'Enrollment reconciliation worker tests',
    'Enrollment Reconciliation Community',
    'https://example.com/logo.png',
    'enrollment-reconciliation-community'
);

-- Event category used by the reconciliation event
insert into event_category (community_id, event_category_id, name)
values (:'communityID', :'eventCategoryID', 'General');

-- Group category used by the reconciliation group
insert into group_category (community_id, group_category_id, name)
values (:'communityID', :'groupCategoryID', 'Technology');

-- Users owning due, future, and queued enrollment state
insert into "user" (auth_hash, email, email_verified, user_id, username)
values
    ('hash-future', 'future@example.com', true, :'futureRecipientID', 'future'),
    ('hash-queue', 'queue@example.com', true, :'queueRecipientID', 'queue'),
    ('hash-recipient', 'recipient@example.com', true, :'recipientID', 'recipient'),
    ('hash-rsvp-queue', 'rsvp-queue@example.com', true, :'rsvpQueueRecipientID', 'rsvp-queue'),
    ('hash-rsvp-recipient', 'rsvp-recipient@example.com', true, :'rsvpRecipientID', 'rsvp-recipient');

-- Group with a configured recipient for paid queue recovery
insert into "group" (
    community_id,
    group_category_id,
    group_id,
    name,
    payment_recipient,
    slug
)
values (
    :'communityID',
    :'groupCategoryID',
    :'groupID',
    'Enrollment Reconciliation Group',
    '{"provider": "stripe", "recipient_id": "acct_reconciliation_worker", "seller_display_name": "Worker Fiscal Sponsor"}'::jsonb,
    'enrollment-reconciliation-group'
);

-- Published event with one due and one future admission offer
insert into event (
    description,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    payment_currency_code,
    published,
    slug,
    starts_at,
    timezone
) values (
    'Enrollment reconciliation event',
    :'eventCategoryID',
    :'eventID',
    'in-person',
    :'groupID',
    'Enrollment Reconciliation Event',
    'USD',
    true,
    'enrollment-reconciliation-event',
    current_timestamp + interval '1 day',
    'UTC'
);

-- RSVP event with a due offer and one waiting recipient
insert into event (
    capacity,
    description,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    published,
    slug,
    starts_at,
    timezone,
    waitlist_enabled
) values (
    1,
    'RSVP reconciliation event',
    :'eventCategoryID',
    :'rsvpEventID',
    'in-person',
    :'groupID',
    'RSVP Reconciliation Event',
    true,
    'rsvp-reconciliation-event',
    current_timestamp + interval '1 day',
    'UTC',
    true
);

-- Public ticket tier with capacity remaining after the due offer expires
insert into event_ticket_type (
    event_id,
    event_ticket_type_id,
    "order",
    seats_total,
    title
) values (
    :'eventID',
    :'ticketTypeID',
    1,
    2,
    'General admission'
);

-- Current positive price that requires the configured provider
insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values (
    :'priceWindowID',
    1000,
    :'ticketTypeID'
);

-- RSVP events without a specialized ticket fixture use a default tier
insert into event_ticket_type (
    event_id,
    event_ticket_type_id,
    "order",
    seats_total,
    title
)
select e.event_id, gen_random_uuid(), 1, 1, 'General Admission'
from event e
where not exists (
    select 1
    from event_ticket_type ett
    where ett.event_id = e.event_id
);

-- Current free price for the RSVP event's default tier
insert into event_ticket_price_window (
    amount_minor,
    event_ticket_price_window_id,
    event_ticket_type_id
)
select 0, gen_random_uuid(), ett.event_ticket_type_id
from event_ticket_type ett
where not exists (
    select 1
    from event_ticket_price_window etpw
    where etpw.event_ticket_type_id = ett.event_ticket_type_id
);

-- Due and future offers reserving the ticket tier before reconciliation
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
    (
        :'dueOfferID',
        current_timestamp - interval '2 hours',
        :'eventID',
        :'ticketTypeID',
        current_timestamp - interval '1 hour',
        'waitlist',
        'pending',
        :'recipientID'
    ),
    (
        :'futureOfferID',
        current_timestamp,
        :'eventID',
        :'ticketTypeID',
        current_timestamp + interval '1 hour',
        'waitlist',
        'pending',
        :'futureRecipientID'
    );

-- Queue head blocked until the configured payment provider becomes available
insert into event_waitlist (
    event_id,
    user_id,
    created_at,
    event_ticket_type_id
) values (
    :'eventID',
    :'queueRecipientID',
    current_timestamp,
    :'ticketTypeID'
);

-- Due RSVP offer that releases the event's only seat
insert into admission_offer (
    admission_offer_id,
    created_at,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    user_id
) values (
    :'rsvpDueOfferID',
    current_timestamp - interval '2 hours',
    :'rsvpEventID',
    (select event_ticket_type_id from event_ticket_type where event_id = :'rsvpEventID' limit 1),
    current_timestamp - interval '1 hour',
    'organizer_invitation',
    'pending',
    :'rsvpRecipientID'
);

-- RSVP queue head promoted by background reconciliation
insert into event_waitlist (event_id, event_ticket_type_id, user_id)
values (
    :'rsvpEventID',
    (select event_ticket_type_id from event_ticket_type where event_id = :'rsvpEventID' limit 1),
    :'rsvpQueueRecipientID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should claim and reconcile one event with a due offer
select is(
    reconcile_next_event_enrollment()::jsonb,
    jsonb_build_object(
        'community_id', :'communityID'::uuid,
        'event_id', :'eventID'::uuid,
        'group_id', :'groupID'::uuid
    ),
    'Should claim and reconcile one event with a due offer'
);

-- Should expire the due admission offer
select is(
    (select status from admission_offer where admission_offer_id = :'dueOfferID'),
    'expired',
    'Should expire the due admission offer'
);

-- Should audit the expired admission offer once
select is(
    (
        select count(*)::int
        from audit_log
        where action = 'admission_offer_expired'
        and resource_id = :'dueOfferID'
    ),
    1,
    'Should audit the expired admission offer once'
);

-- Should preserve admission offers whose deadlines are not due
select is(
    (select status from admission_offer where admission_offer_id = :'futureOfferID'),
    'pending',
    'Should preserve admission offers whose deadlines are not due'
);

-- Should reconcile a free queue after an offer expires
select is(
    reconcile_next_event_enrollment()::jsonb,
    jsonb_build_object(
        'community_id', :'communityID'::uuid,
        'event_id', :'rsvpEventID'::uuid,
        'group_id', :'groupID'::uuid
    ),
    'Should reconcile a free queue after an offer expires'
);

-- Should persist a claim offer during background reconciliation
select results_eq(
    format(
        $$
            select
                ao.status,
                not exists (
                    select 1
                    from event_waitlist ew
                    where ew.event_id = %L::uuid
                    and ew.user_id = %L::uuid
                )
            from admission_offer ao
            where ao.event_id = %L::uuid
            and ao.user_id = %L::uuid
        $$,
        :'rsvpEventID',
        :'rsvpQueueRecipientID',
        :'rsvpEventID',
        :'rsvpQueueRecipientID'
    ),
    $$ values ('pending'::text, true) $$,
    'Should persist a claim offer during background reconciliation'
);

-- Should leave a paid queue idle while payment setup is unavailable
select is(
    reconcile_next_event_enrollment()::jsonb,
    null::jsonb,
    'Should leave a paid queue idle while payment setup is unavailable'
);

-- Should resume a paid queue after payment setup becomes available
select is(
    reconcile_next_event_enrollment('stripe')::jsonb,
    jsonb_build_object(
        'community_id', :'communityID'::uuid,
        'event_id', :'eventID'::uuid,
        'group_id', :'groupID'::uuid
    ),
    'Should resume a paid queue after payment setup becomes available'
);

-- Should replace the paid queue head with an admission offer
select results_eq(
    format(
        $$
            select
                ao.event_ticket_type_id,
                ao.source,
                ao.status,
                not exists (
                    select 1
                    from event_waitlist ew
                    where ew.event_id = %L::uuid
                    and ew.event_ticket_type_id = %L::uuid
                    and ew.user_id = %L::uuid
                )
            from admission_offer ao
            where ao.event_id = %L::uuid
            and ao.user_id = %L::uuid
        $$,
        :'eventID',
        :'ticketTypeID',
        :'queueRecipientID',
        :'eventID',
        :'queueRecipientID'
    ),
    format(
        $$
            values (
                %L::uuid,
                'waitlist'::text,
                'pending'::text,
                true
            )
        $$,
        :'ticketTypeID'
    ),
    'Should replace the paid queue head with an admission offer'
);

-- Should return no work after due and promotable enrollment is reconciled
select is(
    reconcile_next_event_enrollment('stripe')::jsonb,
    null::jsonb,
    'Should return no work after due and promotable enrollment is reconciled'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
