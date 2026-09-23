-- Tests searching organizer event waiting lists as one row per person.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(21);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set canceledOfferID '3a300000-0000-0000-0000-00000000000f'
\set claimedOfferID '3a300000-0000-0000-0000-000000000012'
\set claimedUserID '3a300000-0000-0000-0000-000000000013'
\set communityID '3a300000-0000-0000-0000-000000000001'
\set event1ID '3a300000-0000-0000-0000-000000000002'
\set event1TicketTypeID '3a300000-0000-0000-0000-000000000011'
\set eventCategoryID '3a300000-0000-0000-0000-000000000003'
\set eventOfferID '3a300000-0000-0000-0000-00000000000a'
\set eventPersonID '3a300000-0000-0000-0000-000000000014'
\set expiredOfferID '3a300000-0000-0000-0000-000000000010'
\set group2ID '3a300000-0000-0000-0000-000000000004'
\set groupCategoryID '3a300000-0000-0000-0000-000000000005'
\set groupID '3a300000-0000-0000-0000-000000000006'
\set missingEventID '3a300000-0000-0000-0000-000000000007'
\set offerID '3a300000-0000-0000-0000-00000000000b'
\set personPriceWindowID '3a300000-0000-0000-0000-000000000015'
\set personTicketTypeID '3a300000-0000-0000-0000-000000000016'
\set priceWindowID '3a300000-0000-0000-0000-00000000000c'
\set purchaserOfferID '3a300000-0000-0000-0000-000000000017'
\set purchaserPurchaseID '3a300000-0000-0000-0000-000000000018'
\set purchaserUserID '3a300000-0000-0000-0000-000000000019'
\set registeredOfferID '3a300000-0000-0000-0000-00000000001c'
\set registeredUserID '3a300000-0000-0000-0000-00000000001d'
\set requeuedOfferID '3a300000-0000-0000-0000-00000000001e'
\set requeuedUserID '3a300000-0000-0000-0000-00000000001f'
\set supersededCanceledOfferID '3a300000-0000-0000-0000-000000000020'
\set supersededExpiredOfferID '3a300000-0000-0000-0000-000000000021'
\set supersededInvitationOfferID '3a300000-0000-0000-0000-000000000022'
\set supersededUserID '3a300000-0000-0000-0000-000000000023'
\set ticketTypeID '3a300000-0000-0000-0000-00000000000d'
\set tiedHighOfferID '3a300000-0000-0000-0000-00000000001b'
\set tiedLowOfferID '3a300000-0000-0000-0000-00000000001a'
\set tiedUserID '3a300000-0000-0000-0000-000000000024'
\set user1ID '3a300000-0000-0000-0000-000000000008'
\set user1InvitationOfferID '3a300000-0000-0000-0000-000000000025'
\set user2DeclinedOfferID '3a300000-0000-0000-0000-000000000026'
\set user2ID '3a300000-0000-0000-0000-000000000009'
\set user3ID '3a300000-0000-0000-0000-00000000000e'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'group2ID', :'communityID', :'groupCategoryID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID', jsonb_build_object('name', 'General'));

-- Users
select fx_user(:'claimedUserID', jsonb_build_object('username', 'claimed-search-event-waitlist'));
select fx_user(:'purchaserUserID', jsonb_build_object('username', 'purchaser-search-event-waitlist'));
select fx_user(:'registeredUserID', jsonb_build_object('username', 'registered-search-event-waitlist'));
select fx_user(:'requeuedUserID', jsonb_build_object('username', 'requeued-search-event-waitlist'));
select fx_user(:'supersededUserID', jsonb_build_object('username', 'superseded-search-event-waitlist'));
select fx_user(:'tiedUserID', jsonb_build_object('username', 'tied-search-event-waitlist'));
select fx_user(:'user1ID', jsonb_build_object(
    'bio', 'Waits for event capacity',
    'company', 'Cloud Corp',
    'github_url', 'https://github.com/alice',
    'name', 'Alice',
    'photo_url', 'https://example.com/alice.png',
    'provider', '{"github": {"username": "alice-gh", "private": "secret"}, "linuxfoundation": {"username": "alice-lf", "subject": "secret"}}'::jsonb,
    'title', 'Principal Engineer',
    'username', 'alice-search-event-waitlist',
    'website_url', 'https://example.com/alice'
));
select fx_user(:'user2ID', jsonb_build_object(
    'photo_url', 'https://example.com/bob.png',
    'username', 'bob-search-event-waitlist'
));
select fx_user(:'user3ID', jsonb_build_object(
    'name', 'Carol',
    'username', 'carol-search-event-waitlist'
));

-- Events
select fx_event(:'event1ID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 1,
    'published', true,
    'waitlist_enabled', true
));
select fx_event(:'eventOfferID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 1,
    'published', true,
    'waitlist_enabled', true
));
select fx_event(:'eventPersonID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'waitlist_enabled', true
));

-- Ticket type queued by the first event's waitlist entries
select fx_event_ticket_type(:'event1TicketTypeID', :'event1ID', jsonb_build_object(
    'seats_total', 100,
    'title', 'General Admission'
));

-- Ticket type assigned to the promoted-offer event
select fx_event_ticket_type(:'ticketTypeID', :'eventOfferID', jsonb_build_object(
    'seats_total', 1,
    'title', 'General admission'
));

-- Ticket type whose offers exercise the one-row-per-person rules
select fx_event_ticket_type(:'personTicketTypeID', :'eventPersonID', jsonb_build_object(
    'seats_total', 5,
    'title', 'Person admission'
));

-- Free price window for the promoted-offer ticket type
select fx_event_ticket_price_window(:'priceWindowID', :'ticketTypeID', jsonb_build_object('amount_minor', 0));

-- Free price window for the person-row ticket type
select fx_event_ticket_price_window(:'personPriceWindowID', :'personTicketTypeID', jsonb_build_object('amount_minor', 0));

-- Waitlist offers on the promoted-offer event: user1 expired then invited, user2 declined then canceled, user3 pending
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
    (:'expiredOfferID', '2024-01-01 00:00:00+00', :'eventOfferID', :'ticketTypeID', '2024-01-02 00:00:00+00', 'waitlist', 'expired', :'user1ID'),
    (:'user2DeclinedOfferID', '2024-01-02 00:00:00+00', :'eventOfferID', :'ticketTypeID', '2024-01-03 00:00:00+00', 'waitlist', 'declined', :'user2ID'),
    (:'offerID', '2024-01-03 00:00:00+00', :'eventOfferID', :'ticketTypeID', '2099-01-03 10:00:00+00', 'waitlist', 'pending', :'user3ID'),
    (:'canceledOfferID', '2024-01-04 00:00:00+00', :'eventOfferID', :'ticketTypeID', '2024-01-05 00:00:00+00', 'waitlist', 'canceled', :'user2ID'),
    (:'user1InvitationOfferID', '2024-01-06 00:00:00+00', :'eventOfferID', :'ticketTypeID', '2099-01-06 00:00:00+00', 'organizer_invitation', 'pending', :'user1ID');

-- Lapsed waitlist offers on the person-row event, plus the invitation that ended after one of them
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
    (:'requeuedOfferID', '2024-01-01 00:00:00+00', :'eventPersonID', :'personTicketTypeID', '2024-01-02 00:00:00+00', 'waitlist', 'expired', :'requeuedUserID'),
    (:'registeredOfferID', '2024-01-01 00:00:00+00', :'eventPersonID', :'personTicketTypeID', '2024-01-02 00:00:00+00', 'waitlist', 'expired', :'registeredUserID'),
    (:'purchaserOfferID', '2024-01-01 00:00:00+00', :'eventPersonID', :'personTicketTypeID', '2024-01-02 00:00:00+00', 'waitlist', 'expired', :'purchaserUserID'),
    (:'supersededCanceledOfferID', '2024-01-01 00:00:00+00', :'eventPersonID', :'personTicketTypeID', '2024-01-02 00:00:00+00', 'waitlist', 'canceled', :'supersededUserID'),
    (:'supersededExpiredOfferID', '2024-01-03 00:00:00+00', :'eventPersonID', :'personTicketTypeID', '2024-01-04 00:00:00+00', 'waitlist', 'expired', :'supersededUserID'),
    (:'supersededInvitationOfferID', '2024-01-05 00:00:00+00', :'eventPersonID', :'personTicketTypeID', '2024-01-06 00:00:00+00', 'organizer_invitation', 'canceled', :'supersededUserID'),
    (:'tiedLowOfferID', '2024-01-04 00:00:00+00', :'eventPersonID', :'personTicketTypeID', '2024-01-05 00:00:00+00', 'waitlist', 'declined', :'tiedUserID'),
    (:'tiedHighOfferID', '2024-01-04 00:00:00+00', :'eventPersonID', :'personTicketTypeID', '2024-01-05 00:00:00+00', 'waitlist', 'expired', :'tiedUserID');

-- Claimed waitlist offer whose free snapshot confirmed the attendee
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
) values (
    :'claimedOfferID',
    0,
    '2024-01-02 00:00:00+00',
    0,
    :'eventPersonID',
    :'personTicketTypeID',
    '2024-01-03 00:00:00+00',
    'waitlist',
    'completed',
    'Person admission',
    :'claimedUserID'
);

-- Confirmed attendees: one who claimed the offer and one who registered after it lapsed
insert into event_attendee (event_id, status, user_id)
values
    (:'eventPersonID', 'confirmed', :'claimedUserID'),
    (:'eventPersonID', 'confirmed', :'registeredUserID');

-- Pending checkout hold taken after the waitlist offer lapsed
insert into event_purchase (
    amount_minor,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    hold_expires_at,
    status,
    ticket_title,
    user_id
) values (
    0,
    'USD',
    :'eventPersonID',
    :'purchaserPurchaseID',
    :'personTicketTypeID',
    '2099-01-01 00:00:00+00',
    'pending',
    'Person admission',
    :'purchaserUserID'
);

-- Waitlist entries on the first event
insert into event_waitlist (event_id, event_ticket_type_id, user_id, created_at)
values
    (:'event1ID', :'event1TicketTypeID', :'user1ID', '2024-01-01 00:00:00+00'),
    (:'event1ID', :'event1TicketTypeID', :'user2ID', '2024-01-02 00:00:00+00');

-- Queue entry of the user who rejoined after their offer expired
insert into event_waitlist (event_id, event_ticket_type_id, user_id, created_at)
values (:'eventPersonID', :'personTicketTypeID', :'requeuedUserID', '2024-01-07 00:00:00+00');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return waitlist entries with expected fields and FIFO order by default
select is(
    search_event_waitlist(
        :'groupID'::uuid,
        :'event1ID'::uuid,
        jsonb_build_object('limit', 50, 'offset', 0)
    )::jsonb,
    jsonb_build_object(
        'waitlist', '[
            {"created_at": 1704067200, "event_ticket_type_id": "3a300000-0000-0000-0000-000000000011", "ticket_title": "General Admission", "user": {"user_id": "3a300000-0000-0000-0000-000000000008", "username": "alice-search-event-waitlist", "bio": "Waits for event capacity", "company": "Cloud Corp", "github_url": "https://github.com/alice", "name": "Alice", "photo_url": "https://example.com/alice.png", "provider": {"github": {"username": "alice-gh"}, "linuxfoundation": {"username": "alice-lf"}}, "title": "Principal Engineer", "website_url": "https://example.com/alice"}, "waitlist_position": 1},
            {"created_at": 1704153600, "event_ticket_type_id": "3a300000-0000-0000-0000-000000000011", "ticket_title": "General Admission", "user": {"user_id": "3a300000-0000-0000-0000-000000000009", "username": "bob-search-event-waitlist", "photo_url": "https://example.com/bob.png"}, "waitlist_position": 2}
        ]'::jsonb,
        'total', 2
    ),
    'Should return waitlist entries with expected fields and FIFO order by default'
);

-- Should list one row per person with the newest waitlist offer and hide superseded lapsed offers
select is(
    search_event_waitlist(
        :'groupID'::uuid,
        :'eventOfferID'::uuid,
        jsonb_build_object('limit', 50, 'offset', 0)
    )::jsonb,
    format(
        $json$
        {
            "total": 2,
            "waitlist": [
                {
                    "admission_offer_id": "%s",
                    "admission_offer_status": "pending",
                    "created_at": 1704240000,
                    "event_ticket_type_id": "%s",
                    "offer_expires_at": 4071117600,
                    "ticket_title": "General admission",
                    "user": {
                        "name": "Carol",
                        "user_id": "%s",
                        "username": "carol-search-event-waitlist"
                    },
                    "waitlist_position": null
                },
                {
                    "admission_offer_id": "%s",
                    "admission_offer_status": "canceled",
                    "created_at": 1704326400,
                    "event_ticket_type_id": "%s",
                    "offer_expires_at": 1704412800,
                    "ticket_title": "General admission",
                    "user": {
                        "photo_url": "https://example.com/bob.png",
                        "user_id": "%s",
                        "username": "bob-search-event-waitlist"
                    },
                    "waitlist_position": null
                }
            ]
        }
        $json$,
        :'offerID',
        :'ticketTypeID',
        :'user3ID',
        :'canceledOfferID',
        :'ticketTypeID',
        :'user2ID'
    )::jsonb,
    'Should list one row per person with the newest waitlist offer and hide superseded lapsed offers'
);

-- Should hide a lapsed offer after a newer invitation ended without revealing an older offer
select ok(
    not exists (
        select 1
        from jsonb_array_elements(
            search_event_waitlist(
                :'groupID'::uuid,
                :'eventPersonID'::uuid,
                jsonb_build_object('limit', 50, 'offset', 0)
            )::jsonb->'waitlist'
        ) as entry
        where entry#>>'{user,user_id}' = :'supersededUserID'
    ),
    'Should hide a lapsed offer after a newer invitation ended without revealing an older offer'
);

-- Should hide a lapsed offer for a confirmed attendee
select ok(
    not exists (
        select 1
        from jsonb_array_elements(
            search_event_waitlist(
                :'groupID'::uuid,
                :'eventPersonID'::uuid,
                jsonb_build_object('limit', 50, 'offset', 0)
            )::jsonb->'waitlist'
        ) as entry
        where entry#>>'{user,user_id}' = :'registeredUserID'
    ),
    'Should hide a lapsed offer for a confirmed attendee'
);

-- Should hide a lapsed offer for a pending purchase holder
select ok(
    not exists (
        select 1
        from jsonb_array_elements(
            search_event_waitlist(
                :'groupID'::uuid,
                :'eventPersonID'::uuid,
                jsonb_build_object('limit', 50, 'offset', 0)
            )::jsonb->'waitlist'
        ) as entry
        where entry#>>'{user,user_id}' = :'purchaserUserID'
    ),
    'Should hide a lapsed offer for a pending purchase holder'
);

-- Should keep a completed waitlist offer visible
select is(
    (
        select jsonb_build_object(
            'admission_offer_id', entry->>'admission_offer_id',
            'admission_offer_status', entry->>'admission_offer_status'
        )
        from jsonb_array_elements(
            search_event_waitlist(
                :'groupID'::uuid,
                :'eventPersonID'::uuid,
                jsonb_build_object('limit', 50, 'offset', 0)
            )::jsonb->'waitlist'
        ) as entry
        where entry#>>'{user,user_id}' = :'claimedUserID'
    ),
    jsonb_build_object(
        'admission_offer_id', :'claimedOfferID',
        'admission_offer_status', 'completed'
    ),
    'Should keep a completed waitlist offer visible'
);

-- Should paginate one row per person
select is(
    (
        with result as (
            select search_event_waitlist(
                :'groupID'::uuid,
                :'eventPersonID'::uuid,
                jsonb_build_object('limit', 1, 'offset', 1)
            )::jsonb as data
        )
        select jsonb_build_object(
            'rows', jsonb_array_length(data->'waitlist'),
            'total', data->'total',
            'user_id', data#>>'{waitlist,0,user,user_id}'
        )
        from result
    ),
    jsonb_build_object(
        'rows', 1,
        'total', 3,
        'user_id', :'tiedUserID'
    ),
    'Should paginate one row per person'
);

-- Should pick the higher offer identifier when offer timestamps are equal
select is(
    (
        select jsonb_build_object(
            'admission_offer_id', entry->>'admission_offer_id',
            'admission_offer_status', entry->>'admission_offer_status'
        )
        from jsonb_array_elements(
            search_event_waitlist(
                :'groupID'::uuid,
                :'eventPersonID'::uuid,
                jsonb_build_object('limit', 50, 'offset', 0)
            )::jsonb->'waitlist'
        ) as entry
        where entry#>>'{user,user_id}' = :'tiedUserID'
    ),
    jsonb_build_object(
        'admission_offer_id', :'tiedHighOfferID',
        'admission_offer_status', 'expired'
    ),
    'Should pick the higher offer identifier when offer timestamps are equal'
);

-- Should show only the queue row for a user who rejoined after an expired offer
select is(
    (
        select jsonb_build_object(
            'has_offer_fields', entry ? 'admission_offer_id' or entry ? 'admission_offer_status',
            'row_count', count(*) over (),
            'waitlist_position', entry->'waitlist_position'
        )
        from jsonb_array_elements(
            search_event_waitlist(
                :'groupID'::uuid,
                :'eventPersonID'::uuid,
                jsonb_build_object('limit', 50, 'offset', 0)
            )::jsonb->'waitlist'
        ) as entry
        where entry#>>'{user,user_id}' = :'requeuedUserID'
    ),
    jsonb_build_object(
        'has_offer_fields', false,
        'row_count', 1,
        'waitlist_position', 1
    ),
    'Should show only the queue row for a user who rejoined after an expired offer'
);

-- Should return paginated waitlist entries when limit and offset are provided
select is(
    search_event_waitlist(
        :'groupID'::uuid,
        :'event1ID'::uuid,
        jsonb_build_object('limit', 1, 'offset', 1)
    )::jsonb,
    jsonb_build_object(
        'waitlist', '[
            {"created_at": 1704153600, "event_ticket_type_id": "3a300000-0000-0000-0000-000000000011", "ticket_title": "General Admission", "user": {"user_id": "3a300000-0000-0000-0000-000000000009", "username": "bob-search-event-waitlist", "photo_url": "https://example.com/bob.png"}, "waitlist_position": 2}
        ]'::jsonb,
        'total', 2
    ),
    'Should return paginated waitlist entries when limit and offset are provided'
);

-- Should return empty list when event scope is null
select is(
    search_event_waitlist(
        :'groupID'::uuid,
        null::uuid,
        '{"limit":50,"offset":0}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'waitlist', '[]'::jsonb,
        'total', 0
    ),
    'Should return empty list when event scope is null'
);

-- Should return empty list for non-existing event
select is(
    search_event_waitlist(
        :'groupID'::uuid,
        :'missingEventID'::uuid,
        jsonb_build_object('limit', 50, 'offset', 0)
    )::jsonb,
    jsonb_build_object(
        'waitlist', '[]'::jsonb,
        'total', 0
    ),
    'Should return empty list for non-existing event'
);

-- Should return empty list when event belongs to another group
select is(
    search_event_waitlist(
        :'group2ID'::uuid,
        :'event1ID'::uuid,
        jsonb_build_object('limit', 50, 'offset', 0)
    )::jsonb,
    jsonb_build_object(
        'waitlist', '[]'::jsonb,
        'total', 0
    ),
    'Should return empty list when event belongs to another group'
);

-- Should filter waitlist entries by identity search query
select ok(
    (
        with result as (
            select search_event_waitlist(
                :'groupID'::uuid,
                :'event1ID'::uuid,
                jsonb_build_object(
                    'limit', 50,
                    'offset', 0,
                    'ts_query', 'ali'
                )
            )::jsonb as data
        )
        select (data->>'total')::int = 1
        and data#>>'{waitlist,0,user,user_id}' = :'user1ID'
        and data#>>'{waitlist,0,waitlist_position}' = '1'
        from result
    ),
    'Should filter waitlist entries by identity search query'
);

-- Should filter waitlist entries by company search query
select ok(
    (
        with result as (
            select search_event_waitlist(
                :'groupID'::uuid,
                :'event1ID'::uuid,
                jsonb_build_object(
                    'limit', 50,
                    'offset', 0,
                    'ts_query', 'cloud corp'
                )
            )::jsonb as data
        )
        select (data->>'total')::int = 1
        and data#>>'{waitlist,0,user,user_id}' = :'user1ID'
        and data#>>'{waitlist,0,waitlist_position}' = '1'
        from result
    ),
    'Should filter waitlist entries by company search query'
);

-- Should filter waitlist entries by title search query
select ok(
    (
        with result as (
            select search_event_waitlist(
                :'groupID'::uuid,
                :'event1ID'::uuid,
                jsonb_build_object(
                    'limit', 50,
                    'offset', 0,
                    'ts_query', 'principal engineer'
                )
            )::jsonb as data
        )
        select (data->>'total')::int = 1
        and data#>>'{waitlist,0,user,user_id}' = :'user1ID'
        and data#>>'{waitlist,0,waitlist_position}' = '1'
        from result
    ),
    'Should filter waitlist entries by title search query'
);

-- Should sort waitlist entries by name ascending
select is(
    search_event_waitlist(
        :'groupID'::uuid,
        :'event1ID'::uuid,
        jsonb_build_object(
            'limit', 50,
            'offset', 0,
            'sort', 'name-asc'
        )
    )::jsonb#>>'{waitlist,0,user,username}',
    'alice-search-event-waitlist',
    'Should sort waitlist entries by name ascending'
);

-- Should sort waitlist entries by joined date descending
select is(
    search_event_waitlist(
        :'groupID'::uuid,
        :'event1ID'::uuid,
        jsonb_build_object(
            'limit', 50,
            'offset', 0,
            'sort', 'created-at-desc'
        )
    )::jsonb#>>'{waitlist,0,user,username}',
    'bob-search-event-waitlist',
    'Should sort waitlist entries by joined date descending'
);

-- Should filter waitlist entries by title presence
select ok(
    (
        with result as (
            select search_event_waitlist(
                :'groupID'::uuid,
                :'event1ID'::uuid,
                jsonb_build_object(
                    'limit', 50,
                    'offset', 0,
                    'title', 'present'
                )
            )::jsonb as data
        )
        select (data->>'total')::int = 1
        and data#>>'{waitlist,0,user,user_id}' = :'user1ID'
        and data#>>'{waitlist,0,waitlist_position}' = '1'
        from result
    ),
    'Should filter waitlist entries by title presence'
);

-- Should keep real waitlist position when search filters earlier entries
select ok(
    (
        with result as (
            select search_event_waitlist(
                :'groupID'::uuid,
                :'event1ID'::uuid,
                jsonb_build_object(
                    'limit', 50,
                    'offset', 0,
                    'ts_query', 'bob-search-event-waitlist'
                )
            )::jsonb as data
        )
        select (data->>'total')::int = 1
        and data#>>'{waitlist,0,user,user_id}' = :'user2ID'
        and data#>>'{waitlist,0,waitlist_position}' = '2'
        from result
    ),
    'Should keep real waitlist position when search filters earlier entries'
);

-- Should return no waitlist entries when search has no matches
select is(
    search_event_waitlist(
        :'groupID'::uuid,
        :'event1ID'::uuid,
        jsonb_build_object(
            'limit', 50,
            'offset', 0,
            'ts_query', 'missing person'
        )
    )::jsonb,
    jsonb_build_object(
        'waitlist', '[]'::jsonb,
        'total', 0
    ),
    'Should return no waitlist entries when search has no matches'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
