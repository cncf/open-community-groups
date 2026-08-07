-- Seeds schema-68 enrollment shapes for the ticket consolidation upgrade test.

begin;

-- Simulate the schema-68 function catalog before its enrollment APIs are removed
create or replace function complete_non_ticketed_event_admission_offer(
    uuid,
    uuid,
    uuid,
    jsonb,
    uuid
)
returns boolean as $$
    select true;
$$ language sql;

\set activeOfferID '69000000-0000-0000-0000-000000000040'
\set communityID '69000000-0000-0000-0000-000000000001'
\set confirmedUserID '69000000-0000-0000-0000-000000000030'
\set eventCategoryID '69000000-0000-0000-0000-000000000003'
\set groupCategoryID '69000000-0000-0000-0000-000000000002'
\set groupID '69000000-0000-0000-0000-000000000004'
\set limitedEventID '69000000-0000-0000-0000-000000000010'
\set overbookedEventID '69000000-0000-0000-0000-000000000012'
\set overbookedUser1ID '69000000-0000-0000-0000-000000000033'
\set overbookedUser2ID '69000000-0000-0000-0000-000000000034'
\set pastEventID '69000000-0000-0000-0000-000000000011'
\set pastPendingUserID '69000000-0000-0000-0000-000000000032'
\set pendingUserID '69000000-0000-0000-0000-000000000031'
\set privateEventID '69000000-0000-0000-0000-000000000015'
\set privatePriceWindowID '69000000-0000-0000-0000-000000000052'
\set privateRequestUserID '69000000-0000-0000-0000-000000000038'
\set privateTicketTypeID '69000000-0000-0000-0000-000000000022'
\set publicPriceWindowID '69000000-0000-0000-0000-000000000050'
\set publicTicketTypeID '69000000-0000-0000-0000-000000000020'
\set requestUserID '69000000-0000-0000-0000-000000000036'
\set secondaryPriceWindowID '69000000-0000-0000-0000-000000000051'
\set secondaryTicketTypeID '69000000-0000-0000-0000-000000000021'
\set terminalOfferID '69000000-0000-0000-0000-000000000041'
\set terminalOfferUserID '69000000-0000-0000-0000-000000000037'
\set ticketedEventID '69000000-0000-0000-0000-000000000014'
\set unlimitedEventID '69000000-0000-0000-0000-000000000013'
\set waitlistUserID '69000000-0000-0000-0000-000000000035'

-- Community hosting the migration fixtures
insert into community (
    community_id,
    banner_mobile_url,
    banner_url,
    description,
    display_name,
    logo_url,
    name
) values (
    :'communityID',
    'https://example.test/banner-mobile.png',
    'https://example.test/banner.png',
    'Migration upgrade fixtures',
    'Migration Community',
    'https://example.test/logo.png',
    'migration-community'
);

-- Event category shared by the migrated events
insert into event_category (community_id, event_category_id, name)
values (:'communityID', :'eventCategoryID', 'Migration events');

-- Group category used by the migration fixture group
insert into group_category (community_id, group_category_id, name)
values (:'communityID', :'groupCategoryID', 'Migration groups');

-- Group owning every migrated event
insert into "group" (community_id, group_category_id, group_id, name, slug)
values (:'communityID', :'groupCategoryID', :'groupID', 'Migration Group', 'migration-group');

-- Users covering the migrated enrollment states
insert into "user" (auth_hash, email, email_verified, user_id, username)
values
    ('hash', 'confirmed@example.test', true, :'confirmedUserID', 'migration-confirmed'),
    ('hash', 'pending@example.test', true, :'pendingUserID', 'migration-pending'),
    ('hash', 'past@example.test', true, :'pastPendingUserID', 'migration-past'),
    ('hash', 'overbooked-1@example.test', true, :'overbookedUser1ID', 'migration-overbooked-1'),
    ('hash', 'overbooked-2@example.test', true, :'overbookedUser2ID', 'migration-overbooked-2'),
    ('hash', 'waitlist@example.test', true, :'waitlistUserID', 'migration-waitlist'),
    ('hash', 'request@example.test', true, :'requestUserID', 'migration-request'),
    ('hash', 'terminal@example.test', true, :'terminalOfferUserID', 'migration-terminal'),
    ('hash', 'private@example.test', true, :'privateRequestUserID', 'migration-private');

-- Events covering legacy capacity and enrollment shapes
insert into event (
    attendee_approval_required,
    capacity,
    description,
    ends_at,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    published,
    registration_ends_at,
    slug,
    starts_at,
    timezone
) values
    (
        false,
        1,
        'Limited future event',
        '2099-01-01 12:00:00+00',
        :'eventCategoryID',
        :'limitedEventID',
        'in-person',
        :'groupID',
        'Limited Event',
        true,
        '2099-01-01 09:00:00+00',
        'limited-event',
        '2099-01-01 10:00:00+00',
        'UTC'
    ),
    (
        false,
        null,
        'Past event with stale questions',
        '2020-01-01 12:00:00+00',
        :'eventCategoryID',
        :'pastEventID',
        'in-person',
        :'groupID',
        'Past Event',
        true,
        '2020-01-01 09:00:00+00',
        'past-event',
        '2020-01-01 10:00:00+00',
        'UTC'
    ),
    (
        false,
        1,
        'Overbooked event',
        '2099-02-01 12:00:00+00',
        :'eventCategoryID',
        :'overbookedEventID',
        'in-person',
        :'groupID',
        'Overbooked Event',
        true,
        null,
        'overbooked-event',
        '2099-02-01 10:00:00+00',
        'UTC'
    ),
    (
        false,
        null,
        'Unlimited event',
        '2099-03-01 12:00:00+00',
        :'eventCategoryID',
        :'unlimitedEventID',
        'in-person',
        :'groupID',
        'Unlimited Event',
        true,
        null,
        'unlimited-event',
        '2099-03-01 10:00:00+00',
        'UTC'
    ),
    (
        true,
        15,
        'Already ticketed event',
        '2099-04-01 12:00:00+00',
        :'eventCategoryID',
        :'ticketedEventID',
        'in-person',
        :'groupID',
        'Ticketed Event',
        true,
        null,
        'ticketed-event',
        '2099-04-01 10:00:00+00',
        'UTC'
    ),
    (
        true,
        5,
        'Private ticket event',
        '2099-05-01 12:00:00+00',
        :'eventCategoryID',
        :'privateEventID',
        'in-person',
        :'groupID',
        'Private Event',
        true,
        null,
        'private-event',
        '2099-05-01 10:00:00+00',
        'UTC'
    );

-- Existing ticket types preserved by the migration
insert into event_ticket_type (
    availability,
    event_id,
    event_ticket_type_id,
    "order",
    seats_total,
    title
) values
    ('public', :'ticketedEventID', :'publicTicketTypeID', 1, 10, 'Public tier'),
    ('invitation_only', :'ticketedEventID', :'secondaryTicketTypeID', 2, 5, 'Private tier'),
    ('invitation_only', :'privateEventID', :'privateTicketTypeID', 1, 5, 'Private admission');

-- Price windows attached to the existing ticket types
insert into event_ticket_price_window (
    amount_minor,
    event_ticket_price_window_id,
    event_ticket_type_id
) values
    (0, :'publicPriceWindowID', :'publicTicketTypeID'),
    (0, :'secondaryPriceWindowID', :'secondaryTicketTypeID'),
    (0, :'privatePriceWindowID', :'privateTicketTypeID');

-- Active and terminal legacy offers migrated to ticket types
insert into admission_offer (
    admission_offer_id,
    created_at,
    event_id,
    legacy,
    source,
    status,
    user_id
) values
    (
        :'activeOfferID',
        '2026-01-01 10:00:00+00',
        :'limitedEventID',
        true,
        'organizer_invitation',
        'checkout_pending',
        :'pendingUserID'
    ),
    (
        :'terminalOfferID',
        '2025-01-01 10:00:00+00',
        :'ticketedEventID',
        true,
        'organizer_invitation',
        'declined',
        :'terminalOfferUserID'
    );

-- Legacy attendee states migrated to ticket-aware enrollment
insert into event_attendee (created_at, event_id, status, user_id)
values
    ('2026-01-01 09:00:00+00', :'limitedEventID', 'confirmed', :'confirmedUserID'),
    ('2026-01-01 10:30:00+00', :'limitedEventID', 'registration-questions-pending', :'pendingUserID'),
    ('2019-12-01 10:00:00+00', :'pastEventID', 'registration-questions-pending', :'pastPendingUserID'),
    ('2026-01-01 09:00:00+00', :'overbookedEventID', 'confirmed', :'overbookedUser1ID'),
    ('2026-01-01 09:01:00+00', :'overbookedEventID', 'confirmed', :'overbookedUser2ID');

-- Legacy waitlist entry assigned a ticket type by the migration
insert into event_waitlist (event_id, user_id)
values (:'ticketedEventID', :'waitlistUserID');

-- Legacy invitation requests assigned ticket types by the migration
insert into event_invitation_request (event_id, status, user_id)
values
    (:'ticketedEventID', 'pending', :'requestUserID'),
    (:'privateEventID', 'pending', :'privateRequestUserID');

commit;
