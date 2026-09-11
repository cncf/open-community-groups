-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(23);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3a320000-0000-0000-0000-000000000001'
\set discountCode1ID '3a320000-0000-0000-0000-000000000002'
\set discountCode2ID '3a320000-0000-0000-0000-000000000003'
\set discountCode3ID '3a320000-0000-0000-0000-000000000004'
\set discountCodeClearedID '3a320000-0000-0000-0000-000000000013'
\set discountCodeOtherID '3a320000-0000-0000-0000-000000000005'
\set eventCategoryID '3a320000-0000-0000-0000-000000000006'
\set eventClearedID '3a320000-0000-0000-0000-000000000014'
\set eventID '3a320000-0000-0000-0000-000000000007'
\set eventProtectedID '3a320000-0000-0000-0000-000000000008'
\set groupCategoryID '3a320000-0000-0000-0000-000000000009'
\set groupID '3a320000-0000-0000-0000-000000000010'
\set protectedTicketTypeID '3a320000-0000-0000-0000-000000000011'
\set userID '3a320000-0000-0000-0000-000000000012'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories, event categories, users and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'userID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Events
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('event_kind_id', 'virtual'));
select fx_event(:'eventProtectedID', :'groupID', :'eventCategoryID', jsonb_build_object('event_kind_id', 'virtual'));
select fx_event(:'eventClearedID', :'groupID', :'eventCategoryID', jsonb_build_object('event_kind_id', 'virtual'));

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
    (
        :'discountCodeOtherID',
        1500,
        'PROTECT',
        :'eventProtectedID',
        'fixed_amount',
        'Protected discount'
    );

-- Override-on discount code cleared by the explicit clearing scenario
insert into event_discount_code (
    event_discount_code_id,
    code,
    event_id,
    kind,
    title,
    available,
    available_override_active,
    percentage,
    total_available
) values (
    :'discountCodeClearedID',
    'CLEAR5',
    :'eventClearedID',
    'percentage',
    'Cleared discount',
    5,
    true,
    5,
    10
);

-- Protected ticket type and purchase
select fx_event_ticket_type(:'protectedTicketTypeID', :'eventProtectedID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General admission'
));

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
    0,
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

-- Should clear the manual override when the payload clears Uses remaining despite an explicit override flag
select lives_ok(
    format(
        $$select sync_event_discount_codes(
            '%s'::uuid,
            '[
                {
                    "event_discount_code_id": "%s",
                    "active": true,
                    "available_cleared": true,
                    "available_override_active": true,
                    "code": "CLEAR5",
                    "kind": "percentage",
                    "percentage": 5,
                    "title": "Cleared discount",
                    "total_available": 10
                }
            ]'::jsonb
        )$$,
        :'eventClearedID',
        :'discountCodeClearedID'
    ),
    'Should clear the manual override when the payload clears Uses remaining despite an explicit override flag'
);

-- Should store an auto-managed discount after the clear command wins over the override flag
select is(
    (
        select jsonb_build_object(
            'available', available,
            'available_override_active', available_override_active
        )
        from event_discount_code
        where event_discount_code_id = :'discountCodeClearedID'::uuid
    ),
    jsonb_build_object(
        'available', null,
        'available_override_active', false
    ),
    'Should store an auto-managed discount after the clear command wins over the override flag'
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
    'OCG01',
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
    'OCG01',
    'discount code total_available cannot be less than existing redemptions',
    'Should reject lowering total_available below existing redemptions'
);

-- Should reject removing discount codes with redemptions
select throws_ok(
    format(
        $$select sync_event_discount_codes('%s'::uuid, '[]'::jsonb)$$,
        :'eventProtectedID'
    ),
    'OCG01',
    'discount codes with redemptions cannot be removed; deactivate them instead',
    'Should reject removing discount codes with redemptions'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
