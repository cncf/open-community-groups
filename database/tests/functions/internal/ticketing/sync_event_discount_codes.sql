-- Tests syncing event discount codes from the ticketing payload.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(17);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3a320000-0000-0000-0000-000000000001'
\set discountCode1ID '3a320000-0000-0000-0000-000000000002'
\set discountCode2ID '3a320000-0000-0000-0000-000000000003'
\set discountCode3ID '3a320000-0000-0000-0000-000000000004'
\set discountCodeAutoCapID '3a320000-0000-0000-0000-000000000015'
\set discountCodeNullPayloadID '3a320000-0000-0000-0000-000000000016'
\set discountCodeOtherID '3a320000-0000-0000-0000-000000000005'
\set discountCodeOverrideKeptID '3a320000-0000-0000-0000-000000000017'
\set discountCodeOverrideOffID '3a320000-0000-0000-0000-000000000018'
\set discountCodePriorStateID '3a320000-0000-0000-0000-000000000019'
\set eventAutoCapID '3a320000-0000-0000-0000-00000000001a'
\set eventCategoryID '3a320000-0000-0000-0000-000000000006'
\set eventID '3a320000-0000-0000-0000-000000000007'
\set eventNullPayloadID '3a320000-0000-0000-0000-00000000001b'
\set eventOverrideKeptID '3a320000-0000-0000-0000-00000000001c'
\set eventOverrideOffID '3a320000-0000-0000-0000-00000000001d'
\set eventPriorStateID '3a320000-0000-0000-0000-00000000001e'
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

-- One event per scenario, because syncing prunes the codes omitted from the payload
select fx_event(:'eventAutoCapID', :'groupID', :'eventCategoryID', jsonb_build_object('event_kind_id', 'virtual'));
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('event_kind_id', 'virtual'));
select fx_event(:'eventNullPayloadID', :'groupID', :'eventCategoryID', jsonb_build_object('event_kind_id', 'virtual'));
select fx_event(:'eventOverrideKeptID', :'groupID', :'eventCategoryID', jsonb_build_object('event_kind_id', 'virtual'));
select fx_event(:'eventOverrideOffID', :'groupID', :'eventCategoryID', jsonb_build_object('event_kind_id', 'virtual'));
select fx_event(:'eventPriorStateID', :'groupID', :'eventCategoryID', jsonb_build_object('event_kind_id', 'virtual'));
select fx_event(:'eventProtectedID', :'groupID', :'eventCategoryID', jsonb_build_object('event_kind_id', 'virtual'));

-- Discount codes upserted, pruned, deleted by a null payload or protected by a redemption
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
    (:'discountCodeNullPayloadID', 500, 'DROP5', :'eventNullPayloadID', 'fixed_amount', 'Dropped discount'),
    (:'discountCodeOtherID', 1500, 'PROTECT', :'eventProtectedID', 'fixed_amount', 'Protected discount');

-- Discount codes with a stored Uses remaining state: auto-managed, or a manual override of 1
insert into event_discount_code (
    event_discount_code_id,
    amount_minor,
    available,
    available_override_active,
    code,
    event_id,
    kind,
    title,
    total_available
) values
    (:'discountCodeAutoCapID', 500, null, false, 'AUTO5', :'eventAutoCapID', 'fixed_amount', 'Auto discount', 10),
    (:'discountCodeOverrideKeptID', 500, 1, true, 'KEEP5', :'eventOverrideKeptID', 'fixed_amount', 'Kept discount', 5),
    (:'discountCodeOverrideOffID', 500, 1, true, 'OFF5', :'eventOverrideOffID', 'fixed_amount', 'Disabled discount', 5),
    (:'discountCodePriorStateID', 500, 1, true, 'PRIOR5', :'eventPriorStateID', 'fixed_amount', 'Prior discount', 5);

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

-- Should preserve a manual override when payload raises the cap and omits Uses remaining
select lives_ok(
    format(
        $$select sync_event_discount_codes(
            '%s'::uuid,
            '[
                {
                    "event_discount_code_id": "%s",
                    "active": true,
                    "available_override_active": true,
                    "amount_minor": 500,
                    "code": "KEEP5",
                    "kind": "fixed_amount",
                    "title": "Kept discount",
                    "total_available": 8
                }
            ]'::jsonb
        )$$,
        :'eventOverrideKeptID',
        :'discountCodeOverrideKeptID'
    ),
    'Should preserve a manual override when payload raises the cap and omits Uses remaining'
);

-- Should keep the manual override state and store the raised cap after saving a payload without available
select is(
    (
        select jsonb_build_object(
            'available', available,
            'available_override_active', available_override_active,
            'total_available', total_available
        )
        from event_discount_code
        where event_discount_code_id = :'discountCodeOverrideKeptID'::uuid
    ),
    jsonb_build_object(
        'available', 1,
        'available_override_active', true,
        'total_available', 8
    ),
    'Should keep the manual override state and store the raised cap after saving a payload without available'
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
                    "amount_minor": 500,
                    "code": "PRIOR5",
                    "kind": "fixed_amount",
                    "title": "Prior discount",
                    "total_available": 6
                }
            ]'::jsonb
        )$$,
        :'eventPriorStateID',
        :'discountCodePriorStateID'
    ),
    'Should preserve the manual override for payloads that omit the new override flag'
);

-- Should keep the manual override state and store the payload cap when the new override flag is omitted
select is(
    (
        select jsonb_build_object(
            'available', available,
            'available_override_active', available_override_active,
            'total_available', total_available
        )
        from event_discount_code
        where event_discount_code_id = :'discountCodePriorStateID'::uuid
    ),
    jsonb_build_object(
        'available', 1,
        'available_override_active', true,
        'total_available', 6
    ),
    'Should keep the manual override state and store the payload cap when the new override flag is omitted'
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
                    "amount_minor": 500,
                    "available_override_active": false,
                    "code": "OFF5",
                    "kind": "fixed_amount",
                    "title": "Disabled discount",
                    "total_available": 5
                }
            ]'::jsonb
        )$$,
        :'eventOverrideOffID',
        :'discountCodeOverrideOffID'
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
        where event_discount_code_id = :'discountCodeOverrideOffID'::uuid
    ),
    jsonb_build_object(
        'available', null,
        'available_override_active', false
    ),
    'Should store an auto-managed discount after clearing the manual override'
);

-- Should keep an auto-managed discount in auto mode when lowering total_available
select lives_ok(
    format(
        $$select sync_event_discount_codes(
            '%s'::uuid,
            '[{"event_discount_code_id": "%s", "active": true, "available_override_active": false, "amount_minor": 500, "code": "AUTO5", "kind": "fixed_amount", "title": "Auto discount", "total_available": 5}]'::jsonb
        )$$,
        :'eventAutoCapID',
        :'discountCodeAutoCapID'
    ),
    'Should keep an auto-managed discount in auto mode when lowering total_available'
);

-- Should keep auto-managed discounts without a stored manual remaining count and store the lowered cap
select is(
    (
        select jsonb_build_object(
            'available', available,
            'available_override_active', available_override_active,
            'total_available', total_available
        )
        from event_discount_code
        where event_discount_code_id = :'discountCodeAutoCapID'::uuid
    ),
    jsonb_build_object(
        'available', null,
        'available_override_active', false,
        'total_available', 5
    ),
    'Should keep auto-managed discounts without a stored manual remaining count and store the lowered cap'
);

-- Should delete all discount codes when payload is omitted
select lives_ok(
    format(
        $$select sync_event_discount_codes('%s'::uuid, null)$$,
        :'eventNullPayloadID'
    ),
    'Should delete all discount codes when payload is omitted'
);

-- Should leave no discount codes after deleting with a null payload
select is(
    (select count(*) from event_discount_code where event_id = :'eventNullPayloadID'::uuid),
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
