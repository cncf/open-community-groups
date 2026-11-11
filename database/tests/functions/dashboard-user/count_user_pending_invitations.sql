-- Tests counting the pending invitations listed in a user's Invitations tab.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set acceptedUserID 'a5e00039-0000-0000-0000-000000000001'
\set canceledEventID 'a5e00039-0000-0000-0000-000000000002'
\set canceledOfferID 'a5e00039-0000-0000-0000-000000000003'
\set canceledTicketTypeID 'a5e00039-0000-0000-0000-000000000004'
\set canceledUserID 'a5e00039-0000-0000-0000-000000000005'
\set checkoutOfferID 'a5e00039-0000-0000-0000-000000000006'
\set checkoutPurchaseID 'a5e00039-0000-0000-0000-000000000007'
\set checkoutUserID 'a5e00039-0000-0000-0000-000000000008'
\set communityID 'a5e00039-0000-0000-0000-000000000009'
\set completedOfferID 'a5e00039-0000-0000-0000-00000000000a'
\set eventCategoryID 'a5e00039-0000-0000-0000-00000000000b'
\set eventID 'a5e00039-0000-0000-0000-00000000000c'
\set groupCategoryID 'a5e00039-0000-0000-0000-00000000000d'
\set groupID 'a5e00039-0000-0000-0000-00000000000e'
\set inviteeOfferID 'a5e00039-0000-0000-0000-00000000000f'
\set inviteeUserID 'a5e00039-0000-0000-0000-000000000010'
\set lapsedOfferID 'a5e00039-0000-0000-0000-000000000011'
\set lapsedUserID 'a5e00039-0000-0000-0000-000000000012'
\set mixedCanceledOfferID 'a5e00039-0000-0000-0000-000000000013'
\set mixedClaimableOfferID 'a5e00039-0000-0000-0000-000000000014'
\set mixedDeclinedOfferID 'a5e00039-0000-0000-0000-000000000015'
\set mixedUserID 'a5e00039-0000-0000-0000-000000000016'
\set noInvitationsUserID 'a5e00039-0000-0000-0000-000000000017'
\set secondGroupID 'a5e00039-0000-0000-0000-000000000018'
\set ticketTypeID 'a5e00039-0000-0000-0000-000000000019'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community whose team and groups send the invitations
select fx_community(:'communityID', jsonb_build_object('active', true));

-- User whose team invitations were all accepted
select fx_user(:'acceptedUserID');

-- User offered a seat at a canceled event
select fx_user(:'canceledUserID');

-- User with a checkout in progress for an offer
select fx_user(:'checkoutUserID');

-- User with pending team invitations and a claimable offer
select fx_user(:'inviteeUserID');

-- User whose offers lapsed or were completed
select fx_user(:'lapsedUserID');

-- User with counted and excluded invitations of every kind
select fx_user(:'mixedUserID');

-- User without invitations
select fx_user(:'noInvitationsUserID');

-- Pending community team invitations of the invitee and the mixed user
insert into community_team (accepted, community_id, role, user_id)
values
    (false, :'communityID', 'viewer', :'inviteeUserID'),
    (false, :'communityID', 'viewer', :'mixedUserID');

-- Accepted community team invitation
insert into community_team (accepted, community_id, role, user_id)
values (true, :'communityID', 'viewer', :'acceptedUserID');

-- Event category of the community
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category of the community
select fx_group_category(:'groupCategoryID', :'communityID');

-- Active group hosting the events
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object('active', true));

-- Second active group inviting the mixed user to its team
select fx_group(:'secondGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('active', true));

-- Published upcoming event accepting enrollment
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', '2099-01-02 10:00:00+00'
));

-- Published upcoming event that was canceled
select fx_event(:'canceledEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'published', true,
    'starts_at', '2099-01-03 10:00:00+00'
));

-- Accepted group team invitations
insert into group_team (accepted, group_id, role, user_id)
values
    (true, :'groupID', 'viewer', :'acceptedUserID'),
    (true, :'groupID', 'viewer', :'mixedUserID');

-- Pending group team invitations of the invitee and the mixed user
insert into group_team (accepted, group_id, role, user_id)
values
    (false, :'groupID', 'viewer', :'inviteeUserID'),
    (false, :'secondGroupID', 'viewer', :'mixedUserID');

-- Ticket tier of the canceled event
select fx_event_ticket_type(:'canceledTicketTypeID', :'canceledEventID', jsonb_build_object('seats_total', 10));

-- Ticket tier of the open event
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object('seats_total', 10));

-- Pending offers whose deadline has not passed
insert into admission_offer (
    admission_offer_id,
    created_at,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    user_id
)
values
    (
        :'canceledOfferID',
        '2024-01-01 10:00:00+00',
        :'canceledEventID',
        :'canceledTicketTypeID',
        '2099-01-01 10:00:00+00',
        'organizer_invitation',
        'pending',
        :'canceledUserID'
    ),
    (
        :'inviteeOfferID',
        '2024-01-02 10:00:00+00',
        :'eventID',
        :'ticketTypeID',
        '2099-01-01 10:00:00+00',
        'organizer_invitation',
        'pending',
        :'inviteeUserID'
    ),
    (
        :'mixedCanceledOfferID',
        '2024-01-03 10:00:00+00',
        :'canceledEventID',
        :'canceledTicketTypeID',
        '2099-01-01 10:00:00+00',
        'organizer_invitation',
        'pending',
        :'mixedUserID'
    ),
    (
        :'mixedClaimableOfferID',
        '2024-01-04 10:00:00+00',
        :'eventID',
        :'ticketTypeID',
        '2099-01-01 10:00:00+00',
        'organizer_invitation',
        'pending',
        :'mixedUserID'
    );

-- Pending offer whose deadline has passed
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
    :'lapsedOfferID',
    '2024-01-05 10:00:00+00',
    :'eventID',
    :'ticketTypeID',
    '2024-01-06 10:00:00+00',
    'organizer_invitation',
    'pending',
    :'lapsedUserID'
);

-- Declined offer of the mixed user
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
    :'mixedDeclinedOfferID',
    '2024-01-07 10:00:00+00',
    :'eventID',
    :'ticketTypeID',
    '2099-01-01 10:00:00+00',
    'organizer_invitation',
    'declined',
    :'mixedUserID'
);

-- Claimed offers carrying their claim-time price snapshot
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
)
values
    (
        :'checkoutOfferID',
        0,
        '2024-01-08 10:00:00+00',
        0,
        :'eventID',
        :'ticketTypeID',
        '2099-01-01 10:00:00+00',
        'organizer_invitation',
        'checkout_pending',
        'General admission',
        :'checkoutUserID'
    ),
    (
        :'completedOfferID',
        0,
        '2024-01-09 10:00:00+00',
        0,
        :'eventID',
        :'ticketTypeID',
        '2099-01-01 10:00:00+00',
        'organizer_invitation',
        'completed',
        'General admission',
        :'lapsedUserID'
    );

-- Pending free purchase holding the checkout offer's seat
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    charge_model,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    status,
    ticket_title,
    user_id,

    admission_offer_id
) values (
    :'checkoutPurchaseID',
    0,
    'ocg-free',
    :'eventID',
    :'ticketTypeID',
    '2099-01-01 09:00:00+00',
    'pending',
    'General admission',
    :'checkoutUserID',

    :'checkoutOfferID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should count offers with an active pending purchase
select is(
    count_user_pending_invitations(:'checkoutUserID'::uuid),
    1,
    'Should count offers with an active pending purchase'
);

-- Should count pending community and group team invitations and claimable offers
select is(
    count_user_pending_invitations(:'inviteeUserID'::uuid),
    3,
    'Should count pending community and group team invitations and claimable offers'
);

-- Should match the rows listed by the invitation list functions
select results_eq(
    format(
        $$select count_user_pending_invitations(%L::uuid)$$,
        :'mixedUserID'
    ),
    format(
        $$
            select (
                json_array_length(list_user_community_team_invitations(%1$L::uuid))
                + json_array_length(list_user_group_team_invitations(%1$L::uuid))
                + json_array_length(list_user_event_invitations(%1$L::uuid))
            )::int
        $$,
        :'mixedUserID'
    ),
    'Should match the rows listed by the invitation list functions'
);

-- Should not count accepted team invitations
select is(
    count_user_pending_invitations(:'acceptedUserID'::uuid),
    0,
    'Should not count accepted team invitations'
);

-- Should not count expired or completed offers
select is(
    count_user_pending_invitations(:'lapsedUserID'::uuid),
    0,
    'Should not count expired or completed offers'
);

-- Should not count offers on canceled events
select is(
    count_user_pending_invitations(:'canceledUserID'::uuid),
    0,
    'Should not count offers on canceled events'
);

-- Should return zero for a user without invitations
select is(
    count_user_pending_invitations(:'noInvitationsUserID'::uuid),
    0,
    'Should return zero for a user without invitations'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
