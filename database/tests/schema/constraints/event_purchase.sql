-- Tests event purchase constraints.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(24);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set automaticTaxBuyerID 'c0070000-0000-0000-0000-000000000001'
\set communityID 'c0070000-0000-0000-0000-000000000002'
\set completedBuyerID 'c0070000-0000-0000-0000-000000000003'
\set directChargeBaseBuyerID 'c0070000-0000-0000-0000-000000000004'
\set directChargeBasePurchaseID 'c0070000-0000-0000-0000-000000000005'
\set discountCodeID 'c0070000-0000-0000-0000-000000000006'
\set eventCategoryID 'c0070000-0000-0000-0000-000000000007'
\set eventID 'c0070000-0000-0000-0000-000000000008'
\set eventOtherID 'c0070000-0000-0000-0000-000000000009'
\set externalBaseBuyerID 'c0070000-0000-0000-0000-00000000000a'
\set externalBasePurchaseID 'c0070000-0000-0000-0000-00000000000b'
\set externalBuyerID 'c0070000-0000-0000-0000-00000000000c'
\set financialBuyerID 'c0070000-0000-0000-0000-00000000000d'
\set groupCategoryID 'c0070000-0000-0000-0000-00000000000e'
\set groupID 'c0070000-0000-0000-0000-00000000000f'
\set manualTaxBuyerID 'c0070000-0000-0000-0000-000000000010'
\set otherDiscountCodeID 'c0070000-0000-0000-0000-000000000011'
\set otherTicketTypeID 'c0070000-0000-0000-0000-000000000012'
\set provisionalFeeBuyerID 'c0070000-0000-0000-0000-000000000013'
\set ticketTypeID 'c0070000-0000-0000-0000-000000000014'
\set untaxedBaseBuyerID 'c0070000-0000-0000-0000-000000000015'
\set untaxedBasePurchaseID 'c0070000-0000-0000-0000-000000000016'
\set untaxedBuyerID 'c0070000-0000-0000-0000-000000000017'
\set userDiscountAcceptedID 'c0070000-0000-0000-0000-000000000018'
\set userDiscountRejectedID 'c0070000-0000-0000-0000-000000000019'
\set userTicketTypeAcceptedID 'c0070000-0000-0000-0000-00000000001a'
\set userTicketTypeRejectedID 'c0070000-0000-0000-0000-00000000001b'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
select fx_community(:'communityID');

-- Buyer of the accepted automatic-tax checkout
select fx_user(:'automaticTaxBuyerID');

-- Buyer of the accepted completed direct-charge purchase
select fx_user(:'completedBuyerID');

-- Buyer of the direct-charge purchase receiving rejected updates
select fx_user(:'directChargeBaseBuyerID');

-- Buyer of the external purchase receiving rejected updates
select fx_user(:'externalBaseBuyerID');

-- Buyer of the accepted external purchase
select fx_user(:'externalBuyerID');

-- Buyer of the accepted purchase with financial amounts
select fx_user(:'financialBuyerID');

-- Buyer of the accepted manual-tax purchase
select fx_user(:'manualTaxBuyerID');

-- Buyer of the accepted purchase with a full provisional fee
select fx_user(:'provisionalFeeBuyerID');

-- Buyer of the untaxed purchase receiving rejected updates
select fx_user(:'untaxedBaseBuyerID');

-- Buyer of the accepted untaxed purchase
select fx_user(:'untaxedBuyerID');

-- Buyer of the accepted discounted purchase
select fx_user(:'userDiscountAcceptedID');

-- Buyer of the rejected discounted purchase
select fx_user(:'userDiscountRejectedID');

-- Buyer of the accepted ticket type purchase
select fx_user(:'userTicketTypeAcceptedID');

-- Buyer of the rejected ticket type purchase
select fx_user(:'userTicketTypeRejectedID');

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event receiving the purchases
select fx_event(:'eventID', :'groupID', :'eventCategoryID', '{"payment_currency_code": "USD"}');

-- Sibling event owning the foreign ticket type and discount code
select fx_event(:'eventOtherID', :'groupID', :'eventCategoryID', '{"payment_currency_code": "USD"}');

-- Discount code of the purchased event
insert into event_discount_code (
    event_discount_code_id,
    amount_minor,
    code,
    event_id,
    kind,
    title
) values (
    :'discountCodeID',
    100,
    'OWN',
    :'eventID',
    'fixed_amount',
    'Own discount'
);

-- Discount code of the sibling event
insert into event_discount_code (
    event_discount_code_id,
    amount_minor,
    code,
    event_id,
    kind,
    title
) values (
    :'otherDiscountCodeID',
    100,
    'OTHER',
    :'eventOtherID',
    'fixed_amount',
    'Other discount'
);

-- Ticket type of the purchased event
select fx_event_ticket_type(:'ticketTypeID', :'eventID', '{"title": "General admission"}');

-- Ticket type of the sibling event
select fx_event_ticket_type(:'otherTicketTypeID', :'eventOtherID', '{"title": "Other admission"}');

-- Pending manual-tax direct-charge purchase receiving rejected updates
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    charge_model,
    event_id,
    event_ticket_type_id,
    provisional_platform_fee_amount_minor,
    status,
    ticket_title,
    user_id,

    connected_seller_id,
    currency_code,
    payment_provider_id,
    provider_object_account_id,
    seller_snapshot,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    venue_snapshot
) values (
    :'directChargeBasePurchaseID',
    2500,
    'direct-charge',
    :'eventID',
    :'ticketTypeID',
    100,
    'pending',
    'General admission',
    :'directChargeBaseBuyerID',

    'acct_c0070000',
    'USD',
    'stripe',
    'acct_c0070000',
    '{"connected_account_id": "acct_c0070000", "display_name": "Purchase Seller", "provider": "stripe"}'::jsonb,
    'exclusive',
    'manual',
    'professional-event-admission',
    '{}'::jsonb
);

-- Pending external purchase receiving rejected updates
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    charge_model,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id,

    currency_code
) values (
    :'externalBasePurchaseID',
    2500,
    'external',
    :'eventID',
    :'ticketTypeID',
    'pending',
    'General admission',
    :'externalBaseBuyerID',

    'USD'
);

-- Pending untaxed direct-charge purchase receiving rejected updates
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    charge_model,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id,

    connected_seller_id,
    currency_code,
    payment_provider_id,
    provider_object_account_id,
    seller_snapshot,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    venue_snapshot
) values (
    :'untaxedBasePurchaseID',
    2500,
    'direct-charge',
    :'eventID',
    :'ticketTypeID',
    'pending',
    'General admission',
    :'untaxedBaseBuyerID',

    'acct_c0070000',
    'USD',
    'stripe',
    'acct_c0070000',
    '{"connected_account_id": "acct_c0070000", "display_name": "Purchase Seller", "provider": "stripe"}'::jsonb,
    'inclusive',
    'none',
    'professional-event-admission',
    '{}'::jsonb
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept a completed direct-charge purchase with its provider settlement
select lives_ok(
    format(
        $$
            insert into event_purchase (
                amount_minor,
                charge_model,
                event_id,
                event_ticket_type_id,
                status,
                ticket_title,
                user_id,

                connected_seller_id,
                currency_code,
                final_platform_fee_amount_minor,
                payment_provider_id,
                provider_charge_id,
                provider_checkout_session_id,
                provider_object_account_id,
                provider_payment_reference,
                provider_total_minor,
                seller_snapshot,
                subtotal_excluding_tax_minor,
                tax_amount_minor,
                tax_behavior,
                tax_calculation_mode,
                tax_classification,
                venue_snapshot
            ) values (
                2500,
                'direct-charge',
                %L::uuid,
                %L::uuid,
                'completed',
                'General admission',
                %L::uuid,

                'acct_c0070000',
                'USD',
                0,
                'stripe',
                'ch_c0070000_completed',
                'cs_c0070000_completed',
                'acct_c0070000',
                'pi_c0070000_completed',
                2500,
                '{"connected_account_id": "acct_c0070000", "display_name": "Purchase Seller", "provider": "stripe"}'::jsonb,
                2500,
                0,
                'inclusive',
                'manual',
                'professional-event-admission',
                '{}'::jsonb
            )
        $$,
        :'eventID',
        :'ticketTypeID',
        :'completedBuyerID'
    ),
    'Should accept a completed direct-charge purchase with its provider settlement'
);

-- Should accept a direct-charge purchase with consistent financial amounts
select lives_ok(
    format(
        $$
            insert into event_purchase (
                amount_minor,
                charge_model,
                event_id,
                event_ticket_type_id,
                provisional_platform_fee_amount_minor,
                status,
                ticket_title,
                user_id,

                connected_seller_id,
                currency_code,
                final_platform_fee_amount_minor,
                payment_provider_id,
                provider_object_account_id,
                provider_total_minor,
                seller_snapshot,
                subtotal_excluding_tax_minor,
                tax_amount_minor,
                tax_behavior,
                tax_calculation_mode,
                tax_classification,
                venue_snapshot
            ) values (
                2500,
                'direct-charge',
                %L::uuid,
                %L::uuid,
                100,
                'pending',
                'General admission',
                %L::uuid,

                'acct_c0070000',
                'USD',
                100,
                'stripe',
                'acct_c0070000',
                2700,
                '{"connected_account_id": "acct_c0070000", "display_name": "Purchase Seller", "provider": "stripe"}'::jsonb,
                2500,
                200,
                'exclusive',
                'manual',
                'professional-event-admission',
                '{}'::jsonb
            )
        $$,
        :'eventID',
        :'ticketTypeID',
        :'financialBuyerID'
    ),
    'Should accept a direct-charge purchase with consistent financial amounts'
);

-- Should accept a direct-charge purchase whose provisional fee equals its amount
select lives_ok(
    format(
        $$
            insert into event_purchase (
                amount_minor,
                charge_model,
                event_id,
                event_ticket_type_id,
                provisional_platform_fee_amount_minor,
                status,
                ticket_title,
                user_id,

                connected_seller_id,
                currency_code,
                payment_provider_id,
                provider_object_account_id,
                seller_snapshot,
                tax_behavior,
                tax_calculation_mode,
                tax_classification,
                venue_snapshot
            ) values (
                2500,
                'direct-charge',
                %L::uuid,
                %L::uuid,
                2500,
                'pending',
                'General admission',
                %L::uuid,

                'acct_c0070000',
                'USD',
                'stripe',
                'acct_c0070000',
                '{"connected_account_id": "acct_c0070000", "display_name": "Purchase Seller", "provider": "stripe"}'::jsonb,
                'exclusive',
                'manual',
                'professional-event-admission',
                '{}'::jsonb
            )
        $$,
        :'eventID',
        :'ticketTypeID',
        :'provisionalFeeBuyerID'
    ),
    'Should accept a direct-charge purchase whose provisional fee equals its amount'
);

-- Should accept a manual-tax purchase with tax rates
select lives_ok(
    format(
        $$
            insert into event_purchase (
                amount_minor,
                charge_model,
                event_id,
                event_ticket_type_id,
                status,
                ticket_title,
                user_id,

                connected_seller_id,
                currency_code,
                manual_tax_rate_ids,
                payment_provider_id,
                provider_object_account_id,
                seller_snapshot,
                tax_behavior,
                tax_calculation_mode,
                tax_classification,
                venue_snapshot
            ) values (
                2500,
                'direct-charge',
                %L::uuid,
                %L::uuid,
                'pending',
                'General admission',
                %L::uuid,

                'acct_c0070000',
                'USD',
                array['txr_c0070000'],
                'stripe',
                'acct_c0070000',
                '{"connected_account_id": "acct_c0070000", "display_name": "Purchase Seller", "provider": "stripe"}'::jsonb,
                'exclusive',
                'manual',
                'professional-event-admission',
                '{}'::jsonb
            )
        $$,
        :'eventID',
        :'ticketTypeID',
        :'manualTaxBuyerID'
    ),
    'Should accept a manual-tax purchase with tax rates'
);

-- Should accept a purchase whose discount code belongs to its event
select lives_ok(
    format(
        $$
            insert into event_purchase (
                amount_minor,
                charge_model,
                currency_code,
                discount_amount_minor,
                event_discount_code_id,
                event_id,
                event_ticket_type_id,
                status,
                ticket_title,
                user_id,

                discount_code
            ) values (
                900,
                'external',
                'USD',
                100,
                %L::uuid,
                %L::uuid,
                %L::uuid,
                'pending',
                'General admission',
                %L::uuid,

                'OWN'
            )
        $$,
        :'discountCodeID',
        :'eventID',
        :'ticketTypeID',
        :'userDiscountAcceptedID'
    ),
    'Should accept a purchase whose discount code belongs to its event'
);

-- Should accept a purchase whose ticket type belongs to its event
select lives_ok(
    format(
        $$
            insert into event_purchase (
                amount_minor,
                event_id,
                event_ticket_type_id,
                status,
                ticket_title,
                user_id
            ) values (
                0,
                %L::uuid,
                %L::uuid,
                'completed',
                'General admission',
                %L::uuid
            )
        $$,
        :'eventID',
        :'ticketTypeID',
        :'userTicketTypeAcceptedID'
    ),
    'Should accept a purchase whose ticket type belongs to its event'
);

-- Should accept an automatic-tax checkout with its tax product
select lives_ok(
    format(
        $$
            insert into event_purchase (
                amount_minor,
                charge_model,
                event_id,
                event_ticket_type_id,
                status,
                ticket_title,
                user_id,

                connected_seller_id,
                currency_code,
                payment_provider_id,
                provider_checkout_session_id,
                provider_object_account_id,
                provider_tax_code,
                provider_tax_location_id,
                provider_tax_product_id,
                seller_snapshot,
                tax_behavior,
                tax_calculation_mode,
                tax_classification,
                venue_snapshot
            ) values (
                2500,
                'direct-charge',
                %L::uuid,
                %L::uuid,
                'pending',
                'General admission',
                %L::uuid,

                'acct_c0070000',
                'USD',
                'stripe',
                'cs_c0070000_automatic',
                'acct_c0070000',
                'txcd_50013001',
                'taxloc_c0070000',
                'prod_c0070000',
                '{"connected_account_id": "acct_c0070000", "display_name": "Purchase Seller", "provider": "stripe"}'::jsonb,
                'exclusive',
                'automatic',
                'professional-event-admission',
                '{}'::jsonb
            )
        $$,
        :'eventID',
        :'ticketTypeID',
        :'automaticTaxBuyerID'
    ),
    'Should accept an automatic-tax checkout with its tax product'
);

-- Should accept an external purchase with payment details
select lives_ok(
    format(
        $$
            insert into event_purchase (
                amount_minor,
                charge_model,
                event_id,
                event_ticket_type_id,
                status,
                ticket_title,
                user_id,

                currency_code,
                external_payment_details
            ) values (
                2500,
                'external',
                %L::uuid,
                %L::uuid,
                'completed',
                'General admission',
                %L::uuid,

                'USD',
                'Paid by bank transfer'
            )
        $$,
        :'eventID',
        :'ticketTypeID',
        :'externalBuyerID'
    ),
    'Should accept an external purchase with payment details'
);

-- Should accept an untaxed purchase with inclusive pricing and zero tax
select lives_ok(
    format(
        $$
            insert into event_purchase (
                amount_minor,
                charge_model,
                event_id,
                event_ticket_type_id,
                status,
                ticket_title,
                user_id,

                connected_seller_id,
                currency_code,
                final_platform_fee_amount_minor,
                payment_provider_id,
                provider_object_account_id,
                provider_total_minor,
                seller_snapshot,
                subtotal_excluding_tax_minor,
                tax_amount_minor,
                tax_behavior,
                tax_calculation_mode,
                tax_classification,
                venue_snapshot
            ) values (
                2500,
                'direct-charge',
                %L::uuid,
                %L::uuid,
                'pending',
                'General admission',
                %L::uuid,

                'acct_c0070000',
                'USD',
                0,
                'stripe',
                'acct_c0070000',
                2500,
                '{"connected_account_id": "acct_c0070000", "display_name": "Purchase Seller", "provider": "stripe"}'::jsonb,
                2500,
                0,
                'inclusive',
                'none',
                'professional-event-admission',
                '{}'::jsonb
            )
        $$,
        :'eventID',
        :'ticketTypeID',
        :'untaxedBuyerID'
    ),
    'Should accept an untaxed purchase with inclusive pricing and zero tax'
);

-- Should reject a completed direct-charge purchase without a provider charge
select throws_ok(
    format(
        $$
            update event_purchase
            set
                final_platform_fee_amount_minor = 0,
                provider_checkout_session_id = 'cs_c0070000_uncharged',
                provider_payment_reference = 'pi_c0070000_uncharged',
                provider_total_minor = 2500,
                status = 'completed',
                subtotal_excluding_tax_minor = 2500,
                tax_amount_minor = 0
            where event_purchase_id = %L::uuid
        $$,
        :'directChargeBasePurchaseID'
    ),
    '23514',
    'new row for relation "event_purchase" violates check constraint "event_purchase_completed_direct_charge_amounts_chk"',
    'Should reject a completed direct-charge purchase without a provider charge'
);

-- Should reject a direct-charge purchase with external payment details
select throws_ok(
    format(
        $$
            update event_purchase
            set external_payment_details = 'Paid by bank transfer'
            where event_purchase_id = %L::uuid
        $$,
        :'directChargeBasePurchaseID'
    ),
    '23514',
    'new row for relation "event_purchase" violates check constraint "event_purchase_external_chk"',
    'Should reject a direct-charge purchase with external payment details'
);

-- Should reject a direct-charge purchase with inconsistent financial amounts
select throws_ok(
    format(
        $$
            update event_purchase
            set
                final_platform_fee_amount_minor = 0,
                provider_total_minor = 2500,
                subtotal_excluding_tax_minor = 2300,
                tax_amount_minor = 100
            where event_purchase_id = %L::uuid
        $$,
        :'directChargeBasePurchaseID'
    ),
    '23514',
    'new row for relation "event_purchase" violates check constraint "event_purchase_financial_amounts_chk"',
    'Should reject a direct-charge purchase with inconsistent financial amounts'
);

-- Should reject a direct-charge purchase whose provisional fee exceeds its amount
select throws_ok(
    format(
        $$
            update event_purchase
            set provisional_platform_fee_amount_minor = 2600
            where event_purchase_id = %L::uuid
        $$,
        :'directChargeBasePurchaseID'
    ),
    '23514',
    'new row for relation "event_purchase" violates check constraint "event_purchase_provisional_platform_fee_amount_minor_chk"',
    'Should reject a direct-charge purchase whose provisional fee exceeds its amount'
);

-- Should reject a direct-charge purchase whose provisional fee is negative
select throws_ok(
    format(
        $$
            update event_purchase
            set provisional_platform_fee_amount_minor = -1
            where event_purchase_id = %L::uuid
        $$,
        :'directChargeBasePurchaseID'
    ),
    '23514',
    'new row for relation "event_purchase" violates check constraint "event_purchase_provisional_platform_fee_amount_minor_chk"',
    'Should reject a direct-charge purchase whose provisional fee is negative'
);

-- Should reject a manual-tax purchase without tax rates
select throws_ok(
    format(
        $$
            update event_purchase
            set manual_tax_rate_ids = '{}'
            where event_purchase_id = %L::uuid
        $$,
        :'directChargeBasePurchaseID'
    ),
    '23514',
    'new row for relation "event_purchase" violates check constraint "event_purchase_manual_tax_rate_ids_chk"',
    'Should reject a manual-tax purchase without tax rates'
);

-- Should reject a purchase whose discount code belongs to another event
select throws_ok(
    format(
        $$
            insert into event_purchase (
                amount_minor,
                charge_model,
                currency_code,
                discount_amount_minor,
                event_discount_code_id,
                event_id,
                event_ticket_type_id,
                status,
                ticket_title,
                user_id,

                discount_code
            ) values (
                900,
                'external',
                'USD',
                100,
                %L::uuid,
                %L::uuid,
                %L::uuid,
                'pending',
                'General admission',
                %L::uuid,

                'OTHER'
            )
        $$,
        :'otherDiscountCodeID',
        :'eventID',
        :'ticketTypeID',
        :'userDiscountRejectedID'
    ),
    '23503',
    'insert or update on table "event_purchase" violates foreign key constraint "event_purchase_event_discount_code_belongs_to_event_fkey"',
    'Should reject a purchase whose discount code belongs to another event'
);

-- Should reject a purchase whose ticket type belongs to another event
select throws_ok(
    format(
        $$
            insert into event_purchase (
                amount_minor,
                event_id,
                event_ticket_type_id,
                status,
                ticket_title,
                user_id
            ) values (
                0,
                %L::uuid,
                %L::uuid,
                'completed',
                'Other admission',
                %L::uuid
            )
        $$,
        :'eventID',
        :'otherTicketTypeID',
        :'userTicketTypeRejectedID'
    ),
    '23503',
    'insert or update on table "event_purchase" violates foreign key constraint "event_purchase_event_ticket_type_belongs_to_event_fkey"',
    'Should reject a purchase whose ticket type belongs to another event'
);

-- Should reject an automatic-tax checkout without its tax product
select throws_ok(
    format(
        $$
            update event_purchase
            set
                provider_checkout_session_id = 'cs_c0070000_untaxed_product',
                provider_tax_code = 'txcd_50013001',
                provider_tax_location_id = 'taxloc_c0070000',
                tax_calculation_mode = 'automatic'
            where event_purchase_id = %L::uuid
        $$,
        :'directChargeBasePurchaseID'
    ),
    '23514',
    'new row for relation "event_purchase" violates check constraint "event_purchase_provider_product_mode_chk"',
    'Should reject an automatic-tax checkout without its tax product'
);

-- Should reject an external purchase with a connected seller
select throws_ok(
    format(
        $$
            update event_purchase
            set connected_seller_id = 'acct_c0070000'
            where event_purchase_id = %L::uuid
        $$,
        :'externalBasePurchaseID'
    ),
    '23514',
    'new row for relation "event_purchase" violates check constraint "event_purchase_external_chk"',
    'Should reject an external purchase with a connected seller'
);

-- Should reject an external purchase with a payment provider
select throws_ok(
    format(
        $$
            update event_purchase
            set payment_provider_id = 'stripe'
            where event_purchase_id = %L::uuid
        $$,
        :'externalBasePurchaseID'
    ),
    '23514',
    'new row for relation "event_purchase" violates check constraint "event_purchase_external_chk"',
    'Should reject an external purchase with a payment provider'
);

-- Should reject an external purchase with a seller snapshot
select throws_ok(
    format(
        $$
            update event_purchase
            set seller_snapshot = '{"connected_account_id": "acct_c0070000", "display_name": "Purchase Seller", "provider": "stripe"}'::jsonb
            where event_purchase_id = %L::uuid
        $$,
        :'externalBasePurchaseID'
    ),
    '23514',
    'new row for relation "event_purchase" violates check constraint "event_purchase_external_chk"',
    'Should reject an external purchase with a seller snapshot'
);

-- Should reject an external purchase with a tax calculation mode
select throws_ok(
    format(
        $$
            update event_purchase
            set tax_calculation_mode = 'none'
            where event_purchase_id = %L::uuid
        $$,
        :'externalBasePurchaseID'
    ),
    '23514',
    'new row for relation "event_purchase" violates check constraint "event_purchase_external_chk"',
    'Should reject an external purchase with a tax calculation mode'
);

-- Should reject an untaxed purchase with a tax amount
select throws_ok(
    format(
        $$
            update event_purchase
            set
                final_platform_fee_amount_minor = 0,
                provider_total_minor = 2500,
                subtotal_excluding_tax_minor = 2400,
                tax_amount_minor = 100
            where event_purchase_id = %L::uuid
        $$,
        :'untaxedBasePurchaseID'
    ),
    '23514',
    'new row for relation "event_purchase" violates check constraint "event_purchase_no_tax_amount_chk"',
    'Should reject an untaxed purchase with a tax amount'
);

-- Should reject an untaxed purchase with exclusive pricing
select throws_ok(
    format(
        $$
            update event_purchase
            set tax_behavior = 'exclusive'
            where event_purchase_id = %L::uuid
        $$,
        :'untaxedBasePurchaseID'
    ),
    '23514',
    'new row for relation "event_purchase" violates check constraint "event_purchase_tax_behavior_chk"',
    'Should reject an untaxed purchase with exclusive pricing'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
