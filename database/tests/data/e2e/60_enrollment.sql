-- E2E seed: admission tiers and event attendees.
-- Depends on: 50_membership_cfs.sql (users, events, teams, and CFS fixtures).

-- Specialized admission tiers must exist before enrollment fixtures
insert into event_ticket_type (
    event_ticket_type_id,
    active,
    event_id,
    "order",
    seats_total,
    title,
    description
)
values (
    '56555555-5555-5555-5555-555555555521',
    true,
    '55555555-5555-5555-5555-555555555522',
    1,
    30,
    'General admission',
    'Standard paid admission used for ticket editor coverage.'
), (
    '56555555-5555-5555-5555-555555555522',
    true,
    '55555555-5555-5555-5555-555555555522',
    2,
    10,
    'Community ticket',
    'Free community allocation used for zero-price ticket coverage.'
), (
    '56555555-5555-5555-5555-555555555524',
    true,
    '55555555-5555-5555-5555-555555555522',
    3,
    2,
    'Backstage pass',
    'Future sale window used for unavailable ticket coverage.'
), (
    '56555555-5555-5555-5555-555555555523',
    true,
    '55555555-5555-5555-5555-555555555523',
    1,
    20,
    'VIP pass',
    'Paid pass used for organizer refund review coverage.'
), (
    '56555555-5555-5555-5555-555555555525',
    true,
    '55555555-5555-5555-5555-555555555506',
    1,
    20,
    'Hybrid admission pass',
    'Physical admission with virtual access used for the homepage hybrid event price badge.'
), (
    '56555555-5555-5555-5555-555555555526',
    true,
    '55555555-5555-5555-5555-555555555507',
    1,
    30,
    'Observability summit pass',
    'Sellable tier used to show a price badge on the homepage in-person events list.'
), (
    '56555555-5555-5555-5555-555555555901',
    true,
    '55555555-5555-5555-5555-555555555901',
    1,
    30,
    'Registration window pass',
    'Sellable pass used for closed registration window coverage.'
), (
    '56555555-5555-5555-5555-555555555902',
    true,
    '55555555-5555-5555-5555-555555555902',
    1,
    30,
    'Registration window pass',
    'Sellable pass used for future registration window coverage.'
), (
    '56555555-5555-5555-5555-555555555903',
    true,
    '55555555-5555-5555-5555-555555555903',
    1,
    30,
    'Registration window pass',
    'Sellable pass used for open registration window coverage.'
), (
    '56555555-5555-5555-5555-555555555911',
    true,
    '55555555-5555-5555-5555-555555555911',
    1,
    30,
    'Registration window pass',
    'Sellable pass used for pending payment dashboard coverage.'
), (
    '56555555-5555-5555-5555-555555555923',
    true,
    '55555555-5555-5555-5555-555555555923',
    1,
    20,
    'Ended sales pass',
    'Zero-price pass whose only sales window has ended.'
);

insert into event_ticket_type (
    event_ticket_type_id,
    active,
    availability,
    event_id,
    "order",
    seats_total,
    title,
    description
)
values (
    '56555555-5555-5555-5555-555555555912',
    true,
    'public',
    '55555555-5555-5555-5555-555555555912',
    1,
    20,
    'Payment return pass',
    'Paid admission used for checkout return coverage.'
), (
    '56555555-5555-5555-5555-555555555913',
    true,
    'public',
    '55555555-5555-5555-5555-555555555913',
    1,
    20,
    'Requested conference pass',
    'Public tier attendees can request for organizer approval.'
), (
    '56555555-5555-5555-5555-655555555913',
    true,
    'invitation_only',
    '55555555-5555-5555-5555-555555555913',
    2,
    5,
    'Private supporter pass',
    'Private tier assigned only through organizer offers.'
), (
    '56555555-5555-5555-5555-555555555914',
    true,
    'public',
    '55555555-5555-5555-5555-555555555914',
    1,
    30,
    'General Admission',
    'Free public RSVP tier used to create unscoped requests.'
), (
    '56555555-5555-5555-5555-655555555914',
    true,
    'invitation_only',
    '55555555-5555-5555-5555-555555555914',
    2,
    4,
    'Sponsor allocation',
    'Private sponsor tier available for organizer assignment.'
), (
    '56555555-5555-5555-5555-755555555914',
    true,
    'invitation_only',
    '55555555-5555-5555-5555-555555555914',
    3,
    4,
    'VIP allocation',
    'Private VIP tier available for organizer assignment.'
), (
    '56555555-5555-5555-5555-555555555915',
    true,
    'public',
    '55555555-5555-5555-5555-555555555915',
    1,
    30,
    'General Admission',
    'Free public RSVP tier used to create unscoped requests.'
), (
    '56555555-5555-5555-5555-655555555915',
    false,
    'invitation_only',
    '55555555-5555-5555-5555-555555555915',
    2,
    4,
    'Inactive private allocation',
    'Inactive tier used to explain why no private ticket can be assigned.'
), (
    '56555555-5555-5555-5555-555555555916',
    true,
    'invitation_only',
    '55555555-5555-5555-5555-555555555916',
    1,
    10,
    'Private paid offer',
    'Paid private tier used by dashboard offer claims.'
), (
    '56555555-5555-5555-5555-555555555917',
    true,
    'public',
    '55555555-5555-5555-5555-555555555917',
    1,
    20,
    'Questions conference pass',
    'Paid tier combined with registration questions.'
), (
    '56555555-5555-5555-5555-555555555918',
    true,
    'public',
    '55555555-5555-5555-5555-555555555918',
    1,
    1,
    'Limited conference pass',
    'Sold-out paid tier used for ticket state and waiting-list coverage.'
), (
    '56555555-5555-5555-5555-555555555919',
    true,
    'public',
    '55555555-5555-5555-5555-555555555919',
    1,
    500,
    'General Admission',
    'Migration fallback tier for a formerly unlimited-capacity event.'
), (
    '56555555-5555-5555-5555-555555555920',
    true,
    'public',
    '55555555-5555-5555-5555-555555555920',
    1,
    1,
    'Refunded conference pass',
    'Paid tier whose prior purchase has been fully refunded.'
), (
    '56555555-5555-5555-5555-555555555921',
    true,
    'public',
    '55555555-5555-5555-5555-555555555921',
    1,
    20,
    'Manual tax pass',
    'Paid tier used for unavailable manual Tax Rate coverage.'
), (
    '56555555-5555-5555-5555-555555555924',
    true,
    'public',
    '55555555-5555-5555-5555-555555555924',
    1,
    8,
    'External admission',
    'Public tier used for the external payment lifecycle.'
), (
    '56555555-5555-5555-5555-555555555925',
    true,
    'public',
    '55555555-5555-5555-5555-555555555925',
    1,
    1,
    'External limited admission',
    'One-seat tier used for external payment capacity races.'
), (
    '56555555-5555-5555-5555-555555555926',
    true,
    'invitation_only',
    '55555555-5555-5555-5555-555555555926',
    1,
    2,
    'External invited admission',
    'Private tier used for external payment invitation claims.'
);

-- Paid tiers used by the Stripe webhook scenarios; defined before the default tier
-- fallback so those events keep a single tier.
insert into event_ticket_type (
    event_ticket_type_id,
    active,
    event_id,
    "order",
    seats_total,
    title,
    description
)
values (
    '56555555-5555-5555-5555-555555555940',
    true,
    '55555555-5555-5555-5555-555555555940',
    1,
    2,
    'Webhook expiration pass',
    'Paid pass used for checkout expiration webhook coverage.'
), (
    '56555555-5555-5555-5555-555555555941',
    true,
    '55555555-5555-5555-5555-555555555941',
    1,
    4,
    'Webhook invoice pass',
    'Paid pass used for invoice webhook coverage.'
), (
    '56555555-5555-5555-5555-555555555942',
    true,
    '55555555-5555-5555-5555-555555555942',
    1,
    1,
    'Webhook refund pass',
    'Paid pass used for refund webhook coverage.'
);

-- Every other event uses one free General Admission tier
insert into event_ticket_type (
    event_id,
    event_ticket_type_id,
    "order",
    seats_total,
    title
)
select
    e.event_id,
    md5(e.event_id::text || ':ticket-type')::uuid,
    1,
    greatest(coalesce(e.capacity, 100), 1),
    'General Admission'
from event e
where not exists (
    select 1
    from event_ticket_type ett
    where ett.event_id = e.event_id
);

-- ============================================================================
-- EVENT ATTENDEES
-- ============================================================================

-- The first attendee is backdated so attendee running totals in analytics
-- span more than one month (analytics_chart renders the empty state otherwise).
insert into event_attendee (event_id, user_id, created_at)
values (
    '55555555-5555-5555-5555-555555555501',
    '77777777-7777-7777-7777-777777777703',
    now() - interval '3 months'
);

insert into event_attendee (event_id, user_id)
values (
    '55555555-5555-5555-5555-555555555501',
    '77777777-7777-7777-7777-777777777705'
), (
    '55555555-5555-5555-5555-555555555504',
    '77777777-7777-7777-7777-777777777705'
), (
    '55555555-5555-5555-5555-555555555520',
    '77777777-7777-7777-7777-777777777705'
), (
    '55555555-5555-5555-5555-555555555521',
    '77777777-7777-7777-7777-777777777703'
), (
    '55555555-5555-5555-5555-555555555526',
    '77777777-7777-7777-7777-777777777703'
), (
    '55555555-5555-5555-5555-555555555523',
    '77777777-7777-7777-7777-777777777705'
), (
    '55555555-5555-5555-5555-555555555523',
    '77777777-7777-7777-7777-777777777706'
), (
    '55555555-5555-5555-5555-555555555523',
    '77777777-7777-7777-7777-777777777707'
), (
    '55555555-5555-5555-5555-555555555523',
    '77777777-7777-7777-7777-777777777708'
), (
    '55555555-5555-5555-5555-555555555523',
    '77777777-7777-7777-7777-777777777712'
), (
    '55555555-5555-5555-5555-555555555523',
    '77777777-7777-7777-7777-777777777703'
), (
    '55555555-5555-5555-5555-555555555529',
    '77777777-7777-7777-7777-777777777708'
);

-- Keep the scanner fixture credential deterministic for browser injection.
update event_attendee
set check_in_code = '99999999-9999-9999-9999-999999999529'
where event_id = '55555555-5555-5555-5555-555555555529'
and user_id = '77777777-7777-7777-7777-777777777708';

insert into event_attendee (event_id, user_id)
values (
    '55555555-5555-5555-5555-555555555912',
    '77777777-7777-7777-7777-777777777711'
), (
    '55555555-5555-5555-5555-555555555918',
    '77777777-7777-7777-7777-777777777703'
);

-- Reviewed invitation requests used by public approval-state coverage.
insert into event_invitation_request (
    event_id,
    user_id,
    status,
    reviewed_at,
    reviewed_by
)
values (
    '55555555-5555-5555-5555-555555555530',
    '77777777-7777-7777-7777-777777777705',
    'accepted',
    now() - interval '1 day',
    '77777777-7777-7777-7777-777777777703'
), (
    '55555555-5555-5555-5555-555555555530',
    '77777777-7777-7777-7777-777777777708',
    'rejected',
    now() - interval '1 day',
    '77777777-7777-7777-7777-777777777703'
);

-- Pending ticket request with registration answers for dashboard review coverage.
insert into event_invitation_request (
    event_id,
    event_ticket_type_id,
    registration_answers,
    status,
    user_id
)
values (
    '55555555-5555-5555-5555-555555555913',
    '56555555-5555-5555-5555-555555555913',
    '{
        "answers": [
            {
                "question_id": "57555555-5555-5555-5555-555555555913",
                "value": "I want to learn how community programs can make technical events more welcoming."
            }
        ]
    }'::jsonb,
    'pending',
    '77777777-7777-7777-7777-777777777707'
);

-- Invitation requests used to verify organizer review outside public windows.
insert into event_invitation_request (
    event_id,
    event_ticket_type_id,
    status,
    user_id,
    reviewed_at,
    reviewed_by
)
values (
    '55555555-5555-5555-5555-555555555905',
    (select event_ticket_type_id from event_ticket_type where event_id = '55555555-5555-5555-5555-555555555905' order by "order" limit 1),
    'pending',
    '77777777-7777-7777-7777-777777777707',
    null,
    null
), (
    '55555555-5555-5555-5555-555555555905',
    (select event_ticket_type_id from event_ticket_type where event_id = '55555555-5555-5555-5555-555555555905' order by "order" limit 1),
    'pending',
    '77777777-7777-7777-7777-777777777708',
    null,
    null
), (
    '55555555-5555-5555-5555-555555555905',
    (select event_ticket_type_id from event_ticket_type where event_id = '55555555-5555-5555-5555-555555555905' order by "order" limit 1),
    'accepted',
    '77777777-7777-7777-7777-777777777705',
    now() - interval '2 days',
    '77777777-7777-7777-7777-777777777703'
), (
    '55555555-5555-5555-5555-555555555922',
    (select event_ticket_type_id from event_ticket_type where event_id = '55555555-5555-5555-5555-555555555922' order by "order" limit 1),
    'pending',
    '77777777-7777-7777-7777-777777777705',
    null,
    null
), (
    '55555555-5555-5555-5555-555555555923',
    '56555555-5555-5555-5555-555555555923',
    'accepted',
    '77777777-7777-7777-7777-777777777707',
    now() - interval '2 days',
    '77777777-7777-7777-7777-777777777703'
);

-- Claimable approval offer pairing member1's accepted invitation request.
insert into admission_offer (
    admission_offer_id,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    user_id
) values (
    '62555555-5555-5555-5555-555555555530',
    '55555555-5555-5555-5555-555555555530',
    (select event_ticket_type_id from event_ticket_type where event_id = '55555555-5555-5555-5555-555555555530' order by "order" limit 1),
    '2099-12-31 00:00:00+00',
    'approval',
    'pending',
    '77777777-7777-7777-7777-777777777705'
);

insert into event_waitlist (event_id, event_ticket_type_id, user_id)
values (
    '55555555-5555-5555-5555-555555555526',
    (select event_ticket_type_id from event_ticket_type where event_id = '55555555-5555-5555-5555-555555555526' order by "order" limit 1),
    '77777777-7777-7777-7777-777777777706'
), (
    '55555555-5555-5555-5555-555555555526',
    (select event_ticket_type_id from event_ticket_type where event_id = '55555555-5555-5555-5555-555555555526' order by "order" limit 1),
    '77777777-7777-7777-7777-777777777707'
);

insert into event_attendee (event_id, user_id, manually_invited, status)
values (
    '55555555-5555-5555-5555-555555555906',
    '77777777-7777-7777-7777-777777777703',
    false,
    'confirmed'
), (
    '55555555-5555-5555-5555-555555555911',
    '77777777-7777-7777-7777-777777777706',
    false,
    'registration-questions-pending'
);

-- Attendees used to verify event cancellation state transitions.
insert into event_attendee (
    event_id,
    user_id,
    checked_in,
    checked_in_at,
    manually_invited,
    status
)
values (
    '55555555-5555-5555-5555-555555555527',
    '77777777-7777-7777-7777-777777777701',
    true,
    now() - interval '1 hour',
    false,
    'confirmed'
);

insert into event_invitation_request (
    event_id,
    event_ticket_type_id,
    status,
    user_id,
    reviewed_at,
    reviewed_by
)
values (
    '55555555-5555-5555-5555-555555555914',
    null,
    'pending',
    '77777777-7777-7777-7777-777777777707',
    null,
    null
), (
    '55555555-5555-5555-5555-555555555914',
    '56555555-5555-5555-5555-555555555914',
    'pending',
    '77777777-7777-7777-7777-777777777708',
    null,
    null
), (
    '55555555-5555-5555-5555-555555555914',
    null,
    'accepted',
    '77777777-7777-7777-7777-777777777702',
    now() - interval '4 days',
    '77777777-7777-7777-7777-777777777703'
), (
    '55555555-5555-5555-5555-555555555914',
    null,
    'accepted',
    '77777777-7777-7777-7777-777777777704',
    now() - interval '2 days',
    '77777777-7777-7777-7777-777777777703'
), (
    '55555555-5555-5555-5555-555555555915',
    null,
    'pending',
    '77777777-7777-7777-7777-777777777710',
    null,
    null
);

-- Claim offers replace the old pending-invitation and pending-question seats
insert into admission_offer (
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    user_id
)
values
    (
        '55555555-5555-5555-5555-555555555909',
        (select event_ticket_type_id from event_ticket_type where event_id = '55555555-5555-5555-5555-555555555909' order by "order" limit 1),
        '2099-12-31 00:00:00+00',
        'waitlist',
        'pending',
        '77777777-7777-7777-7777-777777777706'
    ),
    (
        '55555555-5555-5555-5555-555555555910',
        (select event_ticket_type_id from event_ticket_type where event_id = '55555555-5555-5555-5555-555555555910' order by "order" limit 1),
        '2099-12-31 00:00:00+00',
        'organizer_invitation',
        'pending',
        '77777777-7777-7777-7777-777777777706'
    ),
    (
        '55555555-5555-5555-5555-555555555527',
        (select event_ticket_type_id from event_ticket_type where event_id = '55555555-5555-5555-5555-555555555527' order by "order" limit 1),
        '2099-12-31 00:00:00+00',
        'organizer_invitation',
        'pending',
        '77777777-7777-7777-7777-777777777702'
    ),
    (
        '55555555-5555-5555-5555-555555555527',
        (select event_ticket_type_id from event_ticket_type where event_id = '55555555-5555-5555-5555-555555555527' order by "order" limit 1),
        '2099-12-31 00:00:00+00',
        'waitlist',
        'pending',
        '77777777-7777-7777-7777-777777777704'
    ),
    (
        '55555555-5555-5555-5555-555555555916',
        '56555555-5555-5555-5555-555555555916',
        current_timestamp + interval '7 days',
        'organizer_invitation',
        'pending',
        '77777777-7777-7777-7777-777777777707'
    ),
    (
        '55555555-5555-5555-5555-555555555916',
        '56555555-5555-5555-5555-555555555916',
        current_timestamp + interval '7 days',
        'waitlist',
        'pending',
        '77777777-7777-7777-7777-777777777705'
    );

-- Offers used by outside-window review and ended-price claim coverage.
insert into admission_offer (
    admission_offer_id,
    created_at,
    amount_minor,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    ticket_title,
    user_id
)
values (
    '59555555-5555-5555-5555-555555555905',
    current_timestamp - interval '2 days',
    null,
    null,
    null,
    '55555555-5555-5555-5555-555555555905',
    (select event_ticket_type_id from event_ticket_type where event_id = '55555555-5555-5555-5555-555555555905' order by "order" limit 1),
    current_timestamp - interval '1 day',
    'approval',
    'expired',
    null,
    '77777777-7777-7777-7777-777777777705'
), (
    '59555555-5555-5555-5555-555555555923',
    current_timestamp,
    0,
    null,
    0,
    '55555555-5555-5555-5555-555555555923',
    '56555555-5555-5555-5555-555555555923',
    current_timestamp + interval '5 days',
    'approval',
    'pending',
    'Ended sales pass',
    '77777777-7777-7777-7777-777777777707'
), (
    '59555555-5555-5555-6555-555555555923',
    current_timestamp,
    0,
    null,
    0,
    '55555555-5555-5555-5555-555555555923',
    '56555555-5555-5555-5555-555555555923',
    current_timestamp + interval '5 days',
    'waitlist',
    'pending',
    'Ended sales pass',
    '77777777-7777-7777-7777-777777777708'
);

-- Terminal waitlist offers cover unavailable dashboard action reasons.
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
values (
    '59555555-5555-5555-5555-555555555520',
    current_timestamp - interval '7 days',
    '55555555-5555-5555-5555-555555555520',
    (
        select event_ticket_type_id
        from event_ticket_type
        where event_id = '55555555-5555-5555-5555-555555555520'
        order by "order"
        limit 1
    ),
    current_timestamp - interval '6 days',
    'waitlist',
    'expired',
    '77777777-7777-7777-7777-777777777702'
), (
    '59555555-5555-5555-5555-555555555526',
    current_timestamp - interval '2 days',
    '55555555-5555-5555-5555-555555555526',
    (
        select event_ticket_type_id
        from event_ticket_type
        where event_id = '55555555-5555-5555-5555-555555555526'
        order by "order"
        limit 1
    ),
    current_timestamp - interval '1 day',
    'waitlist',
    'expired',
    '77777777-7777-7777-7777-777777777701'
), (
    '59555555-5555-5555-5555-555555555528',
    current_timestamp - interval '2 days',
    '55555555-5555-5555-5555-555555555528',
    (
        select event_ticket_type_id
        from event_ticket_type
        where event_id = '55555555-5555-5555-5555-555555555528'
        order by "order"
        limit 1
    ),
    current_timestamp + interval '1 day',
    'waitlist',
    'canceled',
    '77777777-7777-7777-7777-777777777705'
), (
    '59555555-5555-5555-5555-555555555914',
    current_timestamp - interval '3 days',
    '55555555-5555-5555-5555-555555555914',
    '56555555-5555-5555-5555-655555555914',
    current_timestamp - interval '2 days',
    'approval',
    'expired',
    '77777777-7777-7777-7777-777777777702'
);

insert into admission_offer (
    admission_offer_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    ticket_title,
    user_id
)
values (
    '59555555-5555-5555-5555-655555555914',
    4500,
    'USD',
    0,
    '55555555-5555-5555-5555-555555555914',
    '56555555-5555-5555-5555-755555555914',
    current_timestamp + interval '5 days',
    'approval',
    'checkout_pending',
    'VIP allocation',
    '77777777-7777-7777-7777-777777777704'
), (
    '59555555-5555-5555-5555-555555555916',
    4000,
    'USD',
    0,
    '55555555-5555-5555-5555-555555555916',
    '56555555-5555-5555-5555-555555555916',
    current_timestamp + interval '5 days',
    'organizer_invitation',
    'checkout_pending',
    'Private paid offer',
    '77777777-7777-7777-7777-777777777708'
);

-- Canceled invitation retained for attendee history regression coverage.
insert into event_attendee (event_id, user_id, manually_invited, status)
values (
    '55555555-5555-5555-5555-555555555528',
    '77777777-7777-7777-7777-777777777702',
    true,
    'invitation-canceled'
);

-- Attendees used by the refund dashboard operational state matrix.
insert into event_attendee (event_id, user_id)
values (
    '55555555-5555-5555-5555-555555555523',
    '77777777-7777-7777-7777-777777777701'
), (
    '55555555-5555-5555-5555-555555555523',
    '77777777-7777-7777-7777-777777777704'
), (
    '55555555-5555-5555-5555-555555555523',
    '77777777-7777-7777-7777-777777777709'
), (
    '55555555-5555-5555-5555-555555555523',
    '77777777-7777-7777-7777-777777777710'
), (
    '55555555-5555-5555-5555-555555555523',
    '77777777-7777-7777-7777-777777777711'
);

insert into event_attendee (event_id, user_id, registration_answers)
values (
    '55555555-5555-5555-5555-555555555525',
    '77777777-7777-7777-7777-777777777705',
    '{
        "answers": [
            {
                "question_id": "57555555-5555-5555-5555-555555555501",
                "value": "I want practical patterns for incident readiness.\nI am also comparing governance models for our internal platform."
            },
            {
                "question_id": "57555555-5555-5555-5555-555555555502",
                "value": "58555555-5555-5555-5555-555555555501"
            },
            {
                "question_id": "57555555-5555-5555-5555-555555555503",
                "value": [
                    "58555555-5555-5555-5555-555555555504",
                    "58555555-5555-5555-5555-555555555505",
                    "58555555-5555-5555-5555-555555555507"
                ]
            },
            {
                "question_id": "57555555-5555-5555-5555-555555555504",
                "value": "Vegetarian lunch if food is provided."
            }
        ]
    }'::jsonb
), (
    '55555555-5555-5555-5555-555555555525',
    '77777777-7777-7777-7777-777777777706',
    '{
        "answers": [
            {
                "question_id": "57555555-5555-5555-5555-555555555501",
                "value": "I am looking for examples of measuring platform adoption without creating vanity metrics."
            },
            {
                "question_id": "57555555-5555-5555-5555-555555555502",
                "value": "58555555-5555-5555-5555-555555555502"
            },
            {
                "question_id": "57555555-5555-5555-5555-555555555503",
                "value": [
                    "58555555-5555-5555-5555-555555555505",
                    "58555555-5555-5555-5555-555555555506"
                ]
            },
            {
                "question_id": "57555555-5555-5555-5555-555555555504",
                "value": "Please share slides after the event."
            }
        ]
    }'::jsonb
), (
    '55555555-5555-5555-5555-555555555525',
    '77777777-7777-7777-7777-777777777707',
    '{
        "answers": [
            {
                "question_id": "57555555-5555-5555-5555-555555555501",
                "value": "I want to understand how other teams introduce reliability reviews."
            },
            {
                "question_id": "57555555-5555-5555-5555-555555555502",
                "value": "58555555-5555-5555-5555-555555555503"
            },
            {
                "question_id": "57555555-5555-5555-5555-555555555503",
                "value": [
                    "58555555-5555-5555-5555-555555555504",
                    "58555555-5555-5555-5555-555555555506",
                    "58555555-5555-5555-5555-555555555507"
                ]
            }
        ]
    }'::jsonb
);
