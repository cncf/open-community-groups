-- Tests RSVP and ticketing conversion guards.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3a510000-0000-0000-0000-000000000001'
\set eventCategoryID '3a510000-0000-0000-0000-000000000002'
\set groupCategoryID '3a510000-0000-0000-0000-000000000003'
\set groupID '3a510000-0000-0000-0000-000000000004'
\set offerUserID '3a510000-0000-0000-0000-000000000005'
\set rsvpOfferEventID '3a510000-0000-0000-0000-000000000006'
\set rsvpWaitlistEventID '3a510000-0000-0000-0000-000000000007'
\set ticketedOfferEventID '3a510000-0000-0000-0000-000000000008'
\set ticketedOfferTicketTypeID '3a510000-0000-0000-0000-000000000009'
\set ticketedWaitlistEventID '3a510000-0000-0000-0000-00000000000a'
\set ticketedWaitlistTicketTypeID '3a510000-0000-0000-0000-00000000000b'
\set validRsvpEventID '3a510000-0000-0000-0000-00000000000c'
\set validRsvpPriceWindowID '3a510000-0000-0000-0000-00000000000d'
\set validRsvpTicketTypeID '3a510000-0000-0000-0000-00000000000e'
\set validTicketedEventID '3a510000-0000-0000-0000-00000000000f'
\set validTicketedTicketTypeID '3a510000-0000-0000-0000-000000000010'
\set waitlistUserID '3a510000-0000-0000-0000-000000000011'

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
    'conversion-guard-community',
    'Conversion Guard Community',
    'Community for event enrollment conversion guard tests',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Categories
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'Meetup');

insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (
    :'groupID',
    :'communityID',
    :'groupCategoryID',
    'Conversion Guard Group',
    'conversion-guard-group'
);

-- Enrollment users
insert into "user" (user_id, auth_hash, email, email_verified, username) values
    (:'offerUserID', 'hash-offer', 'offer@example.test', true, 'offer-user'),
    (:'waitlistUserID', 'hash-waitlist', 'waitlist@example.test', true, 'waitlist-user');

-- RSVP and ticketed events
insert into event (
    event_id,
    capacity,
    description,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    slug,
    timezone,
    waitlist_enabled
) values (
    :'rsvpOfferEventID',
    10,
    'RSVP event with an active offer',
    :'eventCategoryID',
    'virtual',
    :'groupID',
    'RSVP Offer Event',
    'rsvp-offer-event',
    'UTC',
    false
), (
    :'rsvpWaitlistEventID',
    10,
    'RSVP event with a waitlist entry',
    :'eventCategoryID',
    'virtual',
    :'groupID',
    'RSVP Waitlist Event',
    'rsvp-waitlist-event',
    'UTC',
    true
), (
    :'ticketedOfferEventID',
    null,
    'Ticketed event with an active offer',
    :'eventCategoryID',
    'virtual',
    :'groupID',
    'Ticketed Offer Event',
    'ticketed-offer-event',
    'UTC',
    false
), (
    :'ticketedWaitlistEventID',
    null,
    'Ticketed event with a tier waitlist entry',
    :'eventCategoryID',
    'virtual',
    :'groupID',
    'Ticketed Waitlist Event',
    'ticketed-waitlist-event',
    'UTC',
    true
), (
    :'validRsvpEventID',
    10,
    'RSVP event without enrollment state',
    :'eventCategoryID',
    'virtual',
    :'groupID',
    'Valid RSVP Event',
    'valid-rsvp-event',
    'UTC',
    false
), (
    :'validTicketedEventID',
    null,
    'Ticketed event without enrollment state',
    :'eventCategoryID',
    'virtual',
    :'groupID',
    'Valid Ticketed Event',
    'valid-ticketed-event',
    'UTC',
    false
);

-- Existing ticket configuration
insert into event_ticket_type (
    event_ticket_type_id,
    event_id,
    "order",
    seats_total,
    title
) values (
    :'ticketedOfferTicketTypeID',
    :'ticketedOfferEventID',
    1,
    10,
    'General admission'
), (
    :'ticketedWaitlistTicketTypeID',
    :'ticketedWaitlistEventID',
    1,
    10,
    'General admission'
), (
    :'validTicketedTicketTypeID',
    :'validTicketedEventID',
    1,
    10,
    'General admission'
);

insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values
    (gen_random_uuid(), 0, :'ticketedOfferTicketTypeID'),
    (gen_random_uuid(), 0, :'ticketedWaitlistTicketTypeID'),
    (gen_random_uuid(), 0, :'validTicketedTicketTypeID');

-- Enrollment state that blocks conversion
insert into admission_offer (
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    user_id
) values (
    :'rsvpOfferEventID',
    null,
    current_timestamp + interval '1 hour',
    'organizer_invitation',
    'pending',
    :'offerUserID'
), (
    :'ticketedOfferEventID',
    :'ticketedOfferTicketTypeID',
    current_timestamp + interval '1 hour',
    'organizer_invitation',
    'pending',
    :'offerUserID'
);

insert into event_waitlist (event_id, event_ticket_type_id, user_id)
values
    (:'rsvpWaitlistEventID', null, :'waitlistUserID'),
    (
        :'ticketedWaitlistEventID',
        :'ticketedWaitlistTicketTypeID',
        :'waitlistUserID'
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should block RSVP-to-ticketed conversion while enrollment state exists
select throws_ok(
    format(
        $$
            select update_event(
                null::uuid,
                %L::uuid,
                %L::uuid,
                jsonb_build_object(
                    'category_id', %L::uuid,
                    'description', 'Updated event',
                    'kind_id', 'virtual',
                    'name', 'Updated Event',
                    'ticket_types', jsonb_build_array(jsonb_build_object(
                        'availability', 'public',
                        'event_ticket_type_id', gen_random_uuid(),
                        'order', 1,
                        'price_windows', jsonb_build_array(jsonb_build_object(
                            'amount_minor', 0,
                            'event_ticket_price_window_id', gen_random_uuid()
                        )),
                        'seats_total', 10,
                        'title', 'General admission'
                    )),
                    'timezone', 'UTC'
                )
            )
        $$,
        :'groupID',
        :'rsvpOfferEventID',
        :'eventCategoryID'
    ),
    'organizer invitations must be resolved before enabling ticketing',
    'Should block ticketing while RSVP offers are active'
);

select throws_ok(
    format(
        $$
            select update_event(
                null::uuid,
                %L::uuid,
                %L::uuid,
                jsonb_build_object(
                    'category_id', %L::uuid,
                    'description', 'Updated event',
                    'kind_id', 'virtual',
                    'name', 'Updated Event',
                    'ticket_types', jsonb_build_array(jsonb_build_object(
                        'availability', 'public',
                        'event_ticket_type_id', gen_random_uuid(),
                        'order', 1,
                        'price_windows', jsonb_build_array(jsonb_build_object(
                            'amount_minor', 0,
                            'event_ticket_price_window_id', gen_random_uuid()
                        )),
                        'seats_total', 10,
                        'title', 'General admission'
                    )),
                    'timezone', 'UTC'
                )
            )
        $$,
        :'groupID',
        :'rsvpWaitlistEventID',
        :'eventCategoryID'
    ),
    'ticketed events cannot have existing event-level waitlist entries',
    'Should block ticketing while event-level waitlist entries exist'
);

-- Should block ticketed-to-RSVP conversion while tier state exists
select throws_ok(
    format(
        $$
            select update_event(
                null::uuid,
                %L::uuid,
                %L::uuid,
                jsonb_build_object(
                    'category_id', %L::uuid,
                    'description', 'Updated event',
                    'kind_id', 'virtual',
                    'name', 'Updated Event',
                    'ticket_types', null,
                    'timezone', 'UTC'
                )
            )
        $$,
        :'groupID',
        :'ticketedOfferEventID',
        :'eventCategoryID'
    ),
    'ticketed enrollment state must be resolved before removing ticket types',
    'Should block RSVP conversion while ticket offers are active'
);

-- Should block RSVP conversion while tier waitlist entries exist
select throws_ok(
    format(
        $$
            select update_event(
                null::uuid,
                %L::uuid,
                %L::uuid,
                jsonb_build_object(
                    'category_id', %L::uuid,
                    'description', 'Updated event',
                    'kind_id', 'virtual',
                    'name', 'Updated Event',
                    'ticket_types', null,
                    'timezone', 'UTC'
                )
            )
        $$,
        :'groupID',
        :'ticketedWaitlistEventID',
        :'eventCategoryID'
    ),
    'ticketed enrollment state must be resolved before removing ticket types',
    'Should block RSVP conversion while tier waitlist entries exist'
);

-- Should allow conversions without blocking enrollment state
select lives_ok(
    format(
        $$
            select update_event(
                null::uuid,
                %L::uuid,
                %L::uuid,
                jsonb_build_object(
                    'category_id', %L::uuid,
                    'description', 'Updated event',
                    'kind_id', 'virtual',
                    'name', 'Updated Event',
                    'ticket_types', jsonb_build_array(jsonb_build_object(
                        'availability', 'public',
                        'event_ticket_type_id', %L::uuid,
                        'order', 1,
                        'price_windows', jsonb_build_array(jsonb_build_object(
                            'amount_minor', 0,
                            'event_ticket_price_window_id', %L::uuid
                        )),
                        'seats_total', 10,
                        'title', 'General admission'
                    )),
                    'timezone', 'UTC'
                )
            )
        $$,
        :'groupID',
        :'validRsvpEventID',
        :'eventCategoryID',
        :'validRsvpTicketTypeID',
        :'validRsvpPriceWindowID'
    ),
    'Should allow RSVP-to-ticketed conversion without enrollment state'
);

select lives_ok(
    format(
        $$
            select update_event(
                null::uuid,
                %L::uuid,
                %L::uuid,
                jsonb_build_object(
                    'category_id', %L::uuid,
                    'description', 'Updated event',
                    'kind_id', 'virtual',
                    'name', 'Updated Event',
                    'ticket_types', null,
                    'timezone', 'UTC'
                )
            )
        $$,
        :'groupID',
        :'validTicketedEventID',
        :'eventCategoryID'
    ),
    'Should allow ticketed-to-RSVP conversion without enrollment state'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
