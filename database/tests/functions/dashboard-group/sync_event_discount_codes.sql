-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(21);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set discountCode1ID '00000000-0000-0000-0000-000000000051'
\set discountCode2ID '00000000-0000-0000-0000-000000000052'
\set discountCode3ID '00000000-0000-0000-0000-000000000053'
\set discountCodeOtherID '00000000-0000-0000-0000-000000000054'
\set eventCategoryID '00000000-0000-0000-0000-000000000011'
\set eventID '00000000-0000-0000-0000-000000000021'
\set eventProtectedID '00000000-0000-0000-0000-000000000022'
\set groupCategoryID '00000000-0000-0000-0000-000000000031'
\set groupID '00000000-0000-0000-0000-000000000041'
\set protectedTicketTypeID '00000000-0000-0000-0000-000000000061'
\set userID '00000000-0000-0000-0000-000000000071'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'community-1', 'Community 1', 'Test community', 'https://e/logo.png', 'https://e/banner-mobile.png', 'https://e/banner.png');

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Group 1', 'group-1');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'Meetup');

-- User
insert into "user" (user_id, auth_hash, email, username, email_verified)
values (:'userID', 'test_hash', 'discount-user@example.test', 'discount-user', true);

-- Events
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id
) values
    (
        :'eventID',
        :'groupID',
        'Discount Codes Event',
        'discount-codes-event',
        'Event used for discount code sync tests',
        'UTC',
        :'eventCategoryID',
        'virtual'
    ),
    (
        :'eventProtectedID',
        :'groupID',
        'Protected Discount Codes Event',
        'protected-discount-codes-event',
        'Event used for protected discount code checks',
        'UTC',
        :'eventCategoryID',
        'virtual'
    );

-- Event discount codes
insert into event_discount_code (
    event_discount_code_id,
    amount_minor,
    code,
    event_id,
    kind,
    title
) values
    (:'discountCode1ID', 500, 'SAVE5', :'eventID', 'fixed_amount', 'Launch discount'),
    (:'discountCode2ID', 1000, 'SAVE10', :'eventID', 'fixed_amount', 'VIP discount'),
    (:'discountCodeOtherID', 1500, 'PROTECT', :'eventProtectedID', 'fixed_amount', 'Protected discount');

-- Protected ticket type and purchase
insert into event_ticket_type (
    event_ticket_type_id,
    event_id,
    "order",
    seats_total,
    title
) values (
    :'protectedTicketTypeID',
    :'eventProtectedID',
    1,
    10,
    'General admission'
);

-- Event purchase
insert into event_purchase (
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
    2500,
    'USD',
    'PROTECT',
    :'discountCodeOtherID',
    :'eventProtectedID',
    :'protectedTicketTypeID',
    'completed',
    'General admission',
    :'userID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should upsert payload discount codes and remove omitted codes
select lives_ok(
    format(
        $$select sync_event_discount_codes(
            '%s'::uuid,
            '[
                {
                    "event_discount_code_id": "%s",
                    "active": false,
                    "amount_minor": 750,
                    "code": "SAVE75",
                    "kind": "fixed_amount",
                    "title": "Launch discount updated"
                },
                {
                    "event_discount_code_id": "%s",
                    "active": true,
                    "code": "SAVE15",
                    "kind": "percentage",
                    "percentage": 15,
                    "title": "Alpha discount",
                    "total_available": 25
                }
            ]'::jsonb
        )$$,
        :'eventID',
        :'discountCode1ID',
        :'discountCode3ID'
    ),
    'Should upsert payload discount codes and remove omitted codes'
);

-- Should update existing discount codes
select is(
    (
        select jsonb_build_object(
            'active', active,
            'amount_minor', amount_minor,
            'code', code,
            'title', title
        )
        from event_discount_code
        where event_discount_code_id = :'discountCode1ID'::uuid
    ),
    jsonb_build_object(
        'active', false,
        'amount_minor', 750,
        'code', 'SAVE75',
        'title', 'Launch discount updated'
    ),
    'Should update existing discount codes'
);

-- Should insert new discount codes from the payload
select is(
    (
        select jsonb_build_object(
            'code', code,
            'kind', kind,
            'percentage', percentage,
            'title', title,
            'total_available', total_available
        )
        from event_discount_code
        where event_discount_code_id = :'discountCode3ID'::uuid
    ),
    jsonb_build_object(
        'code', 'SAVE15',
        'kind', 'percentage',
        'percentage', 15,
        'title', 'Alpha discount',
        'total_available', 25
    ),
    'Should insert new discount codes from the payload'
);

-- Should remove discount codes omitted from the payload
select is(
    (select count(*) from event_discount_code where event_discount_code_id = :'discountCode2ID'::uuid),
    0::bigint,
    'Should remove discount codes omitted from the payload'
);

-- Simulate live availability changes before a stale event edit is saved
update event_discount_code
set
    available = 1,
    available_override_active = true,
    total_available = 5
where event_discount_code_id = :'discountCode1ID'::uuid;

-- Should preserve a manual override when payload omits Uses remaining
select lives_ok(
    format(
        $$select sync_event_discount_codes(
            '%s'::uuid,
            '[
                {
                    "event_discount_code_id": "%s",
                    "active": true,
                    "available_override_active": true,
                    "amount_minor": 900,
                    "code": "SAVE90",
                    "kind": "fixed_amount",
                    "title": "Launch discount saved later",
                    "total_available": 5
                }
            ]'::jsonb
        )$$,
        :'eventID',
        :'discountCode1ID'
    ),
    'Should preserve a manual override when payload omits Uses remaining'
);

-- Should keep the manual override state after saving a payload without available
select is(
    (
        select jsonb_build_object(
            'available', available,
            'available_override_active', available_override_active
        )
        from event_discount_code
        where event_discount_code_id = :'discountCode1ID'::uuid
    ),
    jsonb_build_object(
        'available', 1,
        'available_override_active', true
    ),
    'Should keep the manual override state after saving a payload without available'
);

-- Should preserve the manual override for payloads that omit the new override flag
select lives_ok(
    format(
        $$select sync_event_discount_codes(
            '%s'::uuid,
            '[
                {
                    "event_discount_code_id": "%s",
                    "active": true,
                    "amount_minor": 900,
                    "code": "SAVE90",
                    "kind": "fixed_amount",
                    "title": "Launch discount saved later",
                    "total_available": 5
                }
            ]'::jsonb
        )$$,
        :'eventID',
        :'discountCode1ID'
    ),
    'Should preserve the manual override for payloads that omit the new override flag'
);

-- Should keep the manual override state when the new override flag is omitted
select is(
    (
        select jsonb_build_object(
            'available', available,
            'available_override_active', available_override_active
        )
        from event_discount_code
        where event_discount_code_id = :'discountCode1ID'::uuid
    ),
    jsonb_build_object(
        'available', 1,
        'available_override_active', true
    ),
    'Should keep the manual override state when the new override flag is omitted'
);

-- Should clear the manual override when payload disables it
select lives_ok(
    format(
        $$select sync_event_discount_codes(
            '%s'::uuid,
            '[
                {
                    "event_discount_code_id": "%s",
                    "active": true,
                    "amount_minor": 900,
                    "available_override_active": false,
                    "code": "SAVE90",
                    "kind": "fixed_amount",
                    "title": "Launch discount saved later",
                    "total_available": 5
                }
            ]'::jsonb
        )$$,
        :'eventID',
        :'discountCode1ID'
    ),
    'Should clear the manual override when payload disables it'
);

-- Should store an auto-managed discount after clearing the manual override
select is(
    (
        select jsonb_build_object(
            'available', available,
            'available_override_active', available_override_active
        )
        from event_discount_code
        where event_discount_code_id = :'discountCode1ID'::uuid
    ),
    jsonb_build_object(
        'available', null,
        'available_override_active', false
    ),
    'Should store an auto-managed discount after clearing the manual override'
);

-- Simulate an auto-managed limited code before lowering the cap
update event_discount_code
set
    available = null,
    available_override_active = false,
    total_available = 10
where event_discount_code_id = :'discountCodeOtherID'::uuid;

-- Should keep an auto-managed discount in auto mode when lowering total_available
select lives_ok(
    format(
        $$select sync_event_discount_codes(
            '%s'::uuid,
            '[{"event_discount_code_id": "%s", "active": true, "available_override_active": false, "amount_minor": 1500, "code": "PROTECT", "kind": "fixed_amount", "title": "Protected discount", "total_available": 5}]'::jsonb
        )$$,
        :'eventProtectedID',
        :'discountCodeOtherID'
    ),
    'Should keep an auto-managed discount in auto mode when lowering total_available'
);

-- Should keep auto-managed discounts without a stored manual remaining count
select is(
    (
        select jsonb_build_object(
            'available', available,
            'available_override_active', available_override_active
        )
        from event_discount_code
        where event_discount_code_id = :'discountCodeOtherID'::uuid
    ),
    jsonb_build_object(
        'available', null,
        'available_override_active', false
    ),
    'Should keep auto-managed discounts without a stored manual remaining count'
);

-- Simulate the same auto-managed code before increasing the cap
update event_discount_code
set
    available = null,
    available_override_active = false,
    total_available = 5
where event_discount_code_id = :'discountCodeOtherID'::uuid;

-- Should keep an auto-managed discount in auto mode when increasing total_available
select lives_ok(
    format(
        $$select sync_event_discount_codes(
            '%s'::uuid,
            '[{"event_discount_code_id": "%s", "active": true, "available_override_active": false, "amount_minor": 1500, "code": "PROTECT", "kind": "fixed_amount", "title": "Protected discount", "total_available": 8}]'::jsonb
        )$$,
        :'eventProtectedID',
        :'discountCodeOtherID'
    ),
    'Should keep an auto-managed discount in auto mode when increasing total_available'
);

-- Should leave auto-managed discounts without a stored manual remaining count after increasing the cap
select is(
    (
        select jsonb_build_object(
            'available', available,
            'available_override_active', available_override_active
        )
        from event_discount_code
        where event_discount_code_id = :'discountCodeOtherID'::uuid
    ),
    jsonb_build_object(
        'available', null,
        'available_override_active', false
    ),
    'Should leave auto-managed discounts without a stored manual remaining count after increasing the cap'
);

-- Simulate a manual override below the computed remaining uses before raising the cap
update event_discount_code
set
    available = 2,
    available_override_active = true,
    total_available = 5
where event_discount_code_id = :'discountCodeOtherID'::uuid;

-- Should preserve a manual override when increasing total_available
select lives_ok(
    format(
        $$select sync_event_discount_codes(
            '%s'::uuid,
            '[{"event_discount_code_id": "%s", "active": true, "available_override_active": true, "amount_minor": 1500, "code": "PROTECT", "kind": "fixed_amount", "title": "Protected discount", "total_available": 8}]'::jsonb
        )$$,
        :'eventProtectedID',
        :'discountCodeOtherID'
    ),
    'Should preserve a manual override when increasing total_available'
);

-- Should keep the manual override state after increasing total_available
select is(
    (
        select jsonb_build_object(
            'available', available,
            'available_override_active', available_override_active
        )
        from event_discount_code
        where event_discount_code_id = :'discountCodeOtherID'::uuid
    ),
    jsonb_build_object(
        'available', 2,
        'available_override_active', true
    ),
    'Should keep the manual override state after increasing total_available'
);

-- Should delete all discount codes when payload is omitted
select lives_ok(
    format(
        $$select sync_event_discount_codes('%s'::uuid, null)$$,
        :'eventID'
    ),
    'Should delete all discount codes when payload is omitted'
);

-- Should leave no discount codes after deleting with a null payload
select is(
    (select count(*) from event_discount_code where event_id = :'eventID'::uuid),
    0::bigint,
    'Should leave no discount codes after deleting with a null payload'
);

-- Should reject updating a discount code that belongs to another event
select throws_ok(
    format(
        $$select sync_event_discount_codes(
            '%s'::uuid,
            '[{"event_discount_code_id": "%s", "amount_minor": 500, "code": "INVALID", "kind": "fixed_amount", "title": "Invalid"}]'::jsonb
        )$$,
        :'eventID',
        :'discountCodeOtherID'
    ),
    'discount code does not belong to event',
    'Should reject updating a discount code that belongs to another event'
);

-- Should reject lowering total_available below existing redemptions
select throws_ok(
    format(
        $$select sync_event_discount_codes(
            '%s'::uuid,
            '[{"event_discount_code_id": "%s", "amount_minor": 1500, "code": "PROTECT", "kind": "fixed_amount", "title": "Protected discount", "total_available": 0}]'::jsonb
        )$$,
        :'eventProtectedID',
        :'discountCodeOtherID'
    ),
    'discount code total_available cannot be less than existing redemptions',
    'Should reject lowering total_available below existing redemptions'
);

-- Should reject removing discount codes with redemptions
select throws_ok(
    format(
        $$select sync_event_discount_codes('%s'::uuid, '[]'::jsonb)$$,
        :'eventProtectedID'
    ),
    'discount codes with redemptions cannot be removed; deactivate them instead',
    'Should reject removing discount codes with redemptions'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
