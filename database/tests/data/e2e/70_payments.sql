-- E2E seed: ticketing, purchases, and refunds.
-- Depends on: 60_enrollment.sql (admission tiers and attendee fixtures).

-- ============================================================================
-- EVENT TICKETING
-- ============================================================================

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
    5,
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
)
on conflict (event_ticket_type_id) do nothing;

-- Dated windows and codes are truncated to the minute: the event editor submits
-- datetime-local values, so seconds would register as a ticketing change on save.
insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id,
    starts_at,
    ends_at
)
values (
    '57555555-5555-5555-5555-555555555521',
    2500,
    '56555555-5555-5555-5555-555555555521',
    null,
    date_trunc('minute', now()) + interval '45 days'
), (
    '57555555-5555-5555-5555-555555555522',
    3000,
    '56555555-5555-5555-5555-555555555521',
    date_trunc('minute', now()) + interval '45 days 1 minute',
    null
), (
    '57555555-5555-5555-5555-555555555523',
    0,
    '56555555-5555-5555-5555-555555555522',
    null,
    null
), (
    '57555555-5555-5555-5555-555555555525',
    7000,
    '56555555-5555-5555-5555-555555555524',
    date_trunc('minute', now()) + interval '5 days',
    null
), (
    '57555555-5555-5555-5555-555555555524',
    5000,
    '56555555-5555-5555-5555-555555555523',
    null,
    null
), (
    '57555555-5555-5555-5555-555555555526',
    1500,
    '56555555-5555-5555-5555-555555555525',
    null,
    null
), (
    '57555555-5555-5555-5555-555555555527',
    2000,
    '56555555-5555-5555-5555-555555555526',
    null,
    null
), (
    '57555555-5555-5555-5555-555555555901',
    2500,
    '56555555-5555-5555-5555-555555555901',
    null,
    null
), (
    '57555555-5555-5555-5555-555555555902',
    2500,
    '56555555-5555-5555-5555-555555555902',
    null,
    null
), (
    '57555555-5555-5555-5555-555555555903',
    2500,
    '56555555-5555-5555-5555-555555555903',
    null,
    null
), (
    '57555555-5555-5555-5555-555555555911',
    2500,
    '56555555-5555-5555-5555-555555555911',
    null,
    null
), (
    '57555555-5555-5555-5555-555555555923',
    0,
    '56555555-5555-5555-5555-555555555923',
    date_trunc('minute', now()) - interval '2 days',
    date_trunc('minute', now()) - interval '1 day'
), (
    '57555555-5555-5555-5555-555555555912',
    2500,
    '56555555-5555-5555-5555-555555555912',
    null,
    null
), (
    '57555555-5555-5555-5555-555555555913',
    3500,
    '56555555-5555-5555-5555-555555555913',
    null,
    null
), (
    '57555555-5555-5555-5555-655555555913',
    3000,
    '56555555-5555-5555-5555-655555555913',
    null,
    null
), (
    '57555555-5555-5555-5555-555555555914',
    0,
    '56555555-5555-5555-5555-555555555914',
    null,
    null
), (
    '57555555-5555-5555-5555-655555555914',
    0,
    '56555555-5555-5555-5555-655555555914',
    null,
    null
), (
    '57555555-5555-5555-5555-755555555914',
    4500,
    '56555555-5555-5555-5555-755555555914',
    null,
    null
), (
    '57555555-5555-5555-5555-555555555915',
    0,
    '56555555-5555-5555-5555-555555555915',
    null,
    null
), (
    '57555555-5555-5555-5555-655555555915',
    0,
    '56555555-5555-5555-5555-655555555915',
    null,
    null
), (
    '57555555-5555-5555-5555-555555555916',
    4000,
    '56555555-5555-5555-5555-555555555916',
    null,
    null
), (
    '57555555-5555-5555-5555-555555555917',
    3000,
    '56555555-5555-5555-5555-555555555917',
    null,
    null
), (
    '57555555-5555-5555-5555-555555555918',
    3000,
    '56555555-5555-5555-5555-555555555918',
    null,
    null
), (
    '57555555-5555-5555-5555-555555555919',
    0,
    '56555555-5555-5555-5555-555555555919',
    null,
    null
), (
    '57555555-5555-5555-5555-555555555920',
    3000,
    '56555555-5555-5555-5555-555555555920',
    null,
    null
), (
    '57555555-5555-5555-5555-555555555921',
    2500,
    '56555555-5555-5555-5555-555555555921',
    null,
    null
), (
    '57555555-5555-5555-5555-555555555924',
    1234,
    '56555555-5555-5555-5555-555555555924',
    null,
    null
), (
    '57555555-5555-5555-5555-555555555925',
    1000,
    '56555555-5555-5555-5555-555555555925',
    null,
    null
), (
    '57555555-5555-5555-5555-555555555926',
    2000,
    '56555555-5555-5555-5555-555555555926',
    null,
    null
);

-- Default tiers receive one open-ended free price window
insert into event_ticket_price_window (
    amount_minor,
    event_ticket_price_window_id,
    event_ticket_type_id
)
select 0, md5(ett.event_ticket_type_id::text || ':price-window')::uuid, ett.event_ticket_type_id
from event_ticket_type ett
where not exists (
    select 1
    from event_ticket_price_window etpw
    where etpw.event_ticket_type_id = ett.event_ticket_type_id
);

insert into event_discount_code (
    event_discount_code_id,
    active,
    code,
    event_id,
    kind,
    title,
    amount_minor,
    percentage,
    starts_at,
    ends_at,
    total_available,
    available,
    available_override_active
)
values (
    '58555555-5555-5555-5555-555555555521',
    true,
    'SAVE10',
    '55555555-5555-5555-5555-555555555522',
    'fixed_amount',
    'Launch savings',
    1000,
    null,
    null,
    null,
    null,
    null,
    false
), (
    '58555555-5555-5555-5555-555555555522',
    true,
    'EARLY20',
    '55555555-5555-5555-5555-555555555522',
    'percentage',
    'Early supporter',
    null,
    20,
    null,
    null,
    null,
    null,
    false
), (
    '58555555-5555-5555-5555-555555555523',
    true,
    'EXPIRED15',
    '55555555-5555-5555-5555-555555555522',
    'percentage',
    'Expired campaign',
    null,
    15,
    null,
    date_trunc('minute', now()) - interval '1 day',
    null,
    null,
    false
), (
    '58555555-5555-5555-5555-555555555524',
    true,
    'LIMIT5',
    '55555555-5555-5555-5555-555555555522',
    'fixed_amount',
    'Limited campaign',
    500,
    null,
    null,
    null,
    1,
    0,
    true
), (
    '58555555-5555-5555-5555-555555555525',
    true,
    'REVIEW10',
    '55555555-5555-5555-5555-555555555523',
    'fixed_amount',
    'Refund review discount',
    1000,
    null,
    null,
    null,
    1,
    0,
    true
), (
    '58555555-5555-5555-5555-555555555916',
    true,
    'OFFER25',
    '55555555-5555-5555-5555-555555555916',
    'percentage',
    'Offer claimant discount',
    null,
    25,
    null,
    null,
    null,
    null,
    false
), (
    '58555555-5555-5555-5555-555555555917',
    true,
    'FULLCOMP',
    '55555555-5555-5555-5555-555555555917',
    'percentage',
    'Complimentary registration',
    null,
    100,
    null,
    null,
    null,
    null,
    false
), (
    '58555555-5555-5555-5555-555555555924',
    true,
    'EXTERNALFREE',
    '55555555-5555-5555-5555-555555555924',
    'percentage',
    'External complimentary registration',
    null,
    100,
    null,
    null,
    null,
    null,
    false
);

-- ============================================================================
-- EVENT PURCHASES
-- ============================================================================

insert into event_purchase (
    event_purchase_id,
    amount_minor,
    completed_at,
    currency_code,
    discount_amount_minor,
    discount_code,
    event_discount_code_id,
    event_id,
    event_ticket_type_id,
    payment_provider_id,
    provider_checkout_session_id,
    provider_checkout_url,
    provider_payment_reference,
    status,
    ticket_title,
    user_id,

    charge_model,
    connected_seller_id,
    provider_object_account_id,
    seller_snapshot,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    venue_snapshot,
    final_platform_fee_amount_minor,
    provider_charge_id,
    provider_total_minor,
    subtotal_excluding_tax_minor,
    tax_amount_minor
)
values (
    '59555555-5555-5555-5555-555555555521',
    4000,
    now() - interval '2 days',
    'USD',
    1000,
    'REVIEW10',
    '58555555-5555-5555-5555-555555555525',
    '55555555-5555-5555-5555-555555555523',
    '56555555-5555-5555-5555-555555555523',
    'stripe',
    'cs_e2e_refund_pending',
    'https://checkout.stripe.test/cs_e2e_refund_pending',
    'pi_e2e_refund_pending',
    'refund-requested',
    'VIP pass',
    '77777777-7777-7777-7777-777777777705',

    'direct-charge', 'acct_e2e_alpha', 'acct_e2e_alpha',
    '{"connected_account_id":"acct_e2e_alpha","display_name":"E2E Alpha Fiscal Sponsor","provider":"stripe"}'::jsonb,
    'inclusive', 'manual', 'professional-event-admission',
    '{"address":"123 Payment Way","city":"New York","country_code":"US","name":"E2E Admission Hall","state_code":"NY","state_name":"New York","zip_code":"10001"}'::jsonb,
    0, 'ch_e2e_refund_pending', 4000, 4000, 0
), (
    '59555555-5555-5555-5555-555555555522',
    5000,
    now() - interval '3 days',
    'USD',
    0,
    null,
    null,
    '55555555-5555-5555-5555-555555555523',
    '56555555-5555-5555-5555-555555555523',
    'stripe',
    'cs_e2e_refund_retry',
    'https://checkout.stripe.test/cs_e2e_refund_retry',
    'pi_e2e_refund_retry',
    'refund-requested',
    'VIP pass',
    '77777777-7777-7777-7777-777777777706',

    'direct-charge', 'acct_e2e_alpha', 'acct_e2e_alpha',
    '{"connected_account_id":"acct_e2e_alpha","display_name":"E2E Alpha Fiscal Sponsor","provider":"stripe"}'::jsonb,
    'inclusive', 'manual', 'professional-event-admission',
    '{"address":"123 Payment Way","city":"New York","country_code":"US","name":"E2E Admission Hall","state_code":"NY","state_name":"New York","zip_code":"10001"}'::jsonb,
    0, 'ch_e2e_refund_retry', 5000, 5000, 0
), (
    '59555555-5555-5555-5555-555555555523',
    5000,
    now() - interval '4 days',
    'USD',
    0,
    null,
    null,
    '55555555-5555-5555-5555-555555555523',
    '56555555-5555-5555-5555-555555555523',
    'stripe',
    'cs_e2e_refund_rejected',
    'https://checkout.stripe.test/cs_e2e_refund_rejected',
    'pi_e2e_refund_rejected',
    'completed',
    'VIP pass',
    '77777777-7777-7777-7777-777777777707',

    'direct-charge', 'acct_e2e_alpha', 'acct_e2e_alpha',
    '{"connected_account_id":"acct_e2e_alpha","display_name":"E2E Alpha Fiscal Sponsor","provider":"stripe"}'::jsonb,
    'inclusive', 'manual', 'professional-event-admission',
    '{"address":"123 Payment Way","city":"New York","country_code":"US","name":"E2E Admission Hall","state_code":"NY","state_name":"New York","zip_code":"10001"}'::jsonb,
    0, 'ch_e2e_refund_rejected', 5000, 5000, 0
), (
    '59555555-5555-5555-5555-555555555524',
    5000,
    now() - interval '1 day',
    'USD',
    0,
    null,
    null,
    '55555555-5555-5555-5555-555555555523',
    '56555555-5555-5555-5555-555555555523',
    'stripe',
    'cs_e2e_refund_available',
    'https://checkout.stripe.test/cs_e2e_refund_available',
    'pi_e2e_refund_available',
    'completed',
    'VIP pass',
    '77777777-7777-7777-7777-777777777708',

    'direct-charge', 'acct_e2e_alpha', 'acct_e2e_alpha',
    '{"connected_account_id":"acct_e2e_alpha","display_name":"E2E Alpha Fiscal Sponsor","provider":"stripe"}'::jsonb,
    'inclusive', 'manual', 'professional-event-admission',
    '{"address":"123 Payment Way","city":"New York","country_code":"US","name":"E2E Admission Hall","state_code":"NY","state_name":"New York","zip_code":"10001"}'::jsonb,
    0, 'ch_e2e_refund_available', 5000, 5000, 0
), (
    '59555555-5555-5555-5555-555555555525',
    5000,
    now() - interval '5 days',
    'USD',
    0,
    null,
    null,
    '55555555-5555-5555-5555-555555555523',
    '56555555-5555-5555-5555-555555555523',
    'stripe',
    'cs_e2e_refund_approved',
    'https://checkout.stripe.test/cs_e2e_refund_approved',
    'pi_e2e_refund_approved',
    'refund-requested',
    'VIP pass',
    '77777777-7777-7777-7777-777777777712',

    'direct-charge', 'acct_e2e_alpha', 'acct_e2e_alpha',
    '{"connected_account_id":"acct_e2e_alpha","display_name":"E2E Alpha Fiscal Sponsor","provider":"stripe"}'::jsonb,
    'inclusive', 'manual', 'professional-event-admission',
    '{"address":"123 Payment Way","city":"New York","country_code":"US","name":"E2E Admission Hall","state_code":"NY","state_name":"New York","zip_code":"10001"}'::jsonb,
    0, 'ch_e2e_refund_approved', 5000, 5000, 0
);

-- Purchases used by the refund dashboard operational state matrix.
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    completed_at,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    payment_provider_id,
    provider_checkout_session_id,
    provider_checkout_url,
    provider_payment_reference,
    refunded_at,
    status,
    ticket_title,
    user_id,

    charge_model,
    connected_seller_id,
    provider_object_account_id,
    seller_snapshot,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    venue_snapshot,
    final_platform_fee_amount_minor,
    provider_charge_id,
    provider_invoice_id,
    provider_total_minor,
    subtotal_excluding_tax_minor,
    tax_amount_minor
)
values (
    '59555555-5555-5555-5555-555555555526',
    5000,
    now() - interval '6 days',
    'USD',
    0,
    '55555555-5555-5555-5555-555555555523',
    '56555555-5555-5555-5555-555555555523',
    'stripe',
    'cs_e2e_refund_processing',
    'https://checkout.stripe.test/cs_e2e_refund_processing',
    'pi_e2e_refund_processing',
    null,
    'refund-pending',
    'VIP pass',
    '77777777-7777-7777-7777-777777777704',

    'direct-charge', 'acct_e2e_alpha', 'acct_e2e_alpha',
    '{"connected_account_id":"acct_e2e_alpha","display_name":"E2E Alpha Fiscal Sponsor","provider":"stripe"}'::jsonb,
    'inclusive', 'manual', 'professional-event-admission',
    '{"address":"123 Payment Way","city":"New York","country_code":"US","name":"E2E Admission Hall","state_code":"NY","state_name":"New York","zip_code":"10001"}'::jsonb,
    0, 'ch_e2e_refund_processing', null, 5000, 5000, 0
), (
    '59555555-5555-5555-5555-555555555527',
    5000,
    now() - interval '7 days',
    'USD',
    0,
    '55555555-5555-5555-5555-555555555523',
    '56555555-5555-5555-5555-555555555523',
    'stripe',
    'cs_e2e_refund_retryable',
    'https://checkout.stripe.test/cs_e2e_refund_retryable',
    'pi_e2e_refund_retryable',
    null,
    'refund-pending',
    'VIP pass',
    '77777777-7777-7777-7777-777777777711',

    'direct-charge', 'acct_e2e_alpha', 'acct_e2e_alpha',
    '{"connected_account_id":"acct_e2e_alpha","display_name":"E2E Alpha Fiscal Sponsor","provider":"stripe"}'::jsonb,
    'inclusive', 'manual', 'professional-event-admission',
    '{"address":"123 Payment Way","city":"New York","country_code":"US","name":"E2E Admission Hall","state_code":"NY","state_name":"New York","zip_code":"10001"}'::jsonb,
    0, 'ch_e2e_refund_retryable', null, 5000, 5000, 0
), (
    '59555555-5555-5555-5555-555555555528',
    5000,
    now() - interval '8 days',
    'USD',
    0,
    '55555555-5555-5555-5555-555555555523',
    '56555555-5555-5555-5555-555555555523',
    'stripe',
    'cs_e2e_refund_finalized',
    'https://checkout.stripe.test/cs_e2e_refund_finalized',
    'pi_e2e_refund_finalized',
    now() - interval '1 day',
    'refunded',
    'VIP pass',
    '77777777-7777-7777-7777-777777777701',

    'direct-charge', 'acct_e2e_alpha', 'acct_e2e_alpha',
    '{"connected_account_id":"acct_e2e_alpha","display_name":"E2E Alpha Fiscal Sponsor","provider":"stripe"}'::jsonb,
    'inclusive', 'manual', 'professional-event-admission',
    '{"address":"123 Payment Way","city":"New York","country_code":"US","name":"E2E Admission Hall","state_code":"NY","state_name":"New York","zip_code":"10001"}'::jsonb,
    0, 'ch_e2e_refund_finalized', 'in_e2e_refund_finalized', 5000, 5000, 0
), (
    '59555555-5555-5555-5555-555555555529',
    5000,
    now() - interval '9 days',
    'USD',
    0,
    '55555555-5555-5555-5555-555555555523',
    '56555555-5555-5555-5555-555555555523',
    'stripe',
    'cs_e2e_refund_rejection',
    'https://checkout.stripe.test/cs_e2e_refund_rejection',
    'pi_e2e_refund_rejection',
    null,
    'refund-requested',
    'VIP pass',
    '77777777-7777-7777-7777-777777777709',

    'direct-charge', 'acct_e2e_alpha', 'acct_e2e_alpha',
    '{"connected_account_id":"acct_e2e_alpha","display_name":"E2E Alpha Fiscal Sponsor","provider":"stripe"}'::jsonb,
    'inclusive', 'manual', 'professional-event-admission',
    '{"address":"123 Payment Way","city":"New York","country_code":"US","name":"E2E Admission Hall","state_code":"NY","state_name":"New York","zip_code":"10001"}'::jsonb,
    0, 'ch_e2e_refund_rejection', null, 5000, 5000, 0
), (
    '59555555-5555-5555-5555-555555555530',
    5000,
    now() - interval '10 days',
    'USD',
    0,
    '55555555-5555-5555-5555-555555555523',
    '56555555-5555-5555-5555-555555555523',
    'stripe',
    'cs_e2e_refund_recovery_durable',
    'https://checkout.stripe.test/cs_e2e_refund_recovery_durable',
    'pi_e2e_refund_recovery_durable',
    null,
    'refund-requested',
    'VIP pass',
    '77777777-7777-7777-7777-777777777710',

    'direct-charge', 'acct_e2e_alpha', 'acct_e2e_alpha',
    '{"connected_account_id":"acct_e2e_alpha","display_name":"E2E Alpha Fiscal Sponsor","provider":"stripe"}'::jsonb,
    'inclusive', 'manual', 'professional-event-admission',
    '{"address":"123 Payment Way","city":"New York","country_code":"US","name":"E2E Admission Hall","state_code":"NY","state_name":"New York","zip_code":"10001"}'::jsonb,
    0, 'ch_e2e_refund_recovery_durable', null, 5000, 5000, 0
);

-- Durable document history includes past and canceled events independently of
-- the attendee's current event list.
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    completed_at,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    payment_provider_id,
    provider_checkout_session_id,
    provider_checkout_url,
    provider_payment_reference,
    status,
    ticket_title,
    user_id,

    charge_model,
    connected_seller_id,
    provider_object_account_id,
    seller_snapshot,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    venue_snapshot,
    final_platform_fee_amount_minor,
    provider_charge_id,
    provider_invoice_id,
    provider_total_minor,
    subtotal_excluding_tax_minor,
    tax_amount_minor
)
values (
    '59555555-5555-5555-5555-555555555541',
    2500,
    now() - interval '6 days',
    'USD',
    0,
    '55555555-5555-5555-5555-555555555520',
    (
        select event_ticket_type_id
        from event_ticket_type
        where event_id = '55555555-5555-5555-5555-555555555520'
        order by "order"
        limit 1
    ),
    'stripe',
    'cs_e2e_past_document',
    'https://checkout.stripe.test/cs_e2e_past_document',
    'pi_e2e_past_document',
    'completed',
    'General Admission',
    '77777777-7777-7777-7777-777777777701',

    'direct-charge', 'acct_e2e_alpha', 'acct_e2e_alpha',
    '{"connected_account_id":"acct_e2e_alpha","display_name":"E2E Alpha Fiscal Sponsor","provider":"stripe"}'::jsonb,
    'inclusive', 'manual', 'professional-event-admission',
    '{"address":"123 Payment Way","city":"New York","country_code":"US","name":"E2E Admission Hall","state_code":"NY","state_name":"New York","zip_code":"10001"}'::jsonb,
    0, 'ch_e2e_past_document', 'in_e2e_past_document', 2500, 2500, 0
), (
    '59555555-5555-5555-5555-555555555542',
    3500,
    now() - interval '2 days',
    'USD',
    0,
    '55555555-5555-5555-5555-555555555531',
    (
        select event_ticket_type_id
        from event_ticket_type
        where event_id = '55555555-5555-5555-5555-555555555531'
        order by "order"
        limit 1
    ),
    'stripe',
    'cs_e2e_canceled_document',
    'https://checkout.stripe.test/cs_e2e_canceled_document',
    'pi_e2e_canceled_document',
    'refund-recovery-pending',
    'General Admission',
    '77777777-7777-7777-7777-777777777701',

    'direct-charge', 'acct_e2e_alpha', 'acct_e2e_alpha',
    '{"connected_account_id":"acct_e2e_alpha","display_name":"E2E Alpha Fiscal Sponsor","provider":"stripe"}'::jsonb,
    'inclusive', 'manual', 'professional-event-admission',
    '{"address":"123 Payment Way","city":"New York","country_code":"US","name":"E2E Admission Hall","state_code":"NY","state_name":"New York","zip_code":"10001"}'::jsonb,
    0, 'ch_e2e_canceled_document', null, 3500, 3500, 0
);

insert into event_purchase (
    event_purchase_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    payment_provider_id,
    provider_checkout_session_id,
    provider_checkout_url,
    status,
    ticket_title,
    user_id,

    charge_model,
    connected_seller_id,
    provider_object_account_id,
    seller_snapshot,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    venue_snapshot
)
values (
    '59555555-5555-5555-5555-555555555911',
    2500,
    'USD',
    0,
    '55555555-5555-5555-5555-555555555911',
    '56555555-5555-5555-5555-555555555911',
    now() + interval '2 days',
    'stripe',
    'cs_e2e_registration_window_pending',
    'https://example.test/checkout/registration-window-pending',
    'pending',
    'Registration window pass',
    '77777777-7777-7777-7777-777777777706',

    'direct-charge', 'acct_e2e_alpha', 'acct_e2e_alpha',
    '{"connected_account_id":"acct_e2e_alpha","display_name":"E2E Alpha Fiscal Sponsor","provider":"stripe"}'::jsonb,
    'inclusive', 'manual', 'professional-event-admission',
    '{"address":"123 Payment Way","city":"New York","country_code":"US","name":"E2E Admission Hall","state_code":"NY","state_name":"New York","zip_code":"10001"}'::jsonb
), (
    '59555555-5555-5555-5555-555555555912',
    2500,
    'USD',
    0,
    '55555555-5555-5555-5555-555555555522',
    '56555555-5555-5555-5555-555555555521',
    now() + interval '2 days',
    'stripe',
    'cs_e2e_draft_pending',
    'https://example.test/checkout/draft-pending',
    'pending',
    'General admission',
    '77777777-7777-7777-7777-777777777708',

    'direct-charge', 'acct_e2e_alpha', 'acct_e2e_alpha',
    '{"connected_account_id":"acct_e2e_alpha","display_name":"E2E Alpha Fiscal Sponsor","provider":"stripe"}'::jsonb,
    'inclusive', 'manual', 'professional-event-admission',
    '{"address":"123 Payment Way","city":"New York","country_code":"US","name":"E2E Admission Hall","state_code":"NY","state_name":"New York","zip_code":"10001"}'::jsonb
);

insert into event_purchase (
    event_purchase_id,
    amount_minor,
    completed_at,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    payment_provider_id,
    provider_checkout_session_id,
    provider_checkout_url,
    provider_payment_reference,
    status,
    ticket_title,
    user_id,

    charge_model,
    connected_seller_id,
    provider_object_account_id,
    seller_snapshot,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    venue_snapshot,
    final_platform_fee_amount_minor,
    provider_charge_id,
    provider_total_minor,
    subtotal_excluding_tax_minor,
    tax_amount_minor
)
values (
    '59555555-5555-5555-5555-755555555912',
    2500,
    now() - interval '1 day',
    'USD',
    0,
    '55555555-5555-5555-5555-555555555912',
    '56555555-5555-5555-5555-555555555912',
    'stripe',
    'cs_e2e_payment_return_confirmed',
    'https://checkout.stripe.test/cs_e2e_payment_return_confirmed',
    'pi_e2e_payment_return_confirmed',
    'completed',
    'Payment return pass',
    '77777777-7777-7777-7777-777777777711',

    'direct-charge', 'acct_e2e_alpha', 'acct_e2e_alpha',
    '{"connected_account_id":"acct_e2e_alpha","display_name":"E2E Alpha Fiscal Sponsor","provider":"stripe"}'::jsonb,
    'inclusive', 'manual', 'professional-event-admission',
    '{"address":"123 Payment Way","city":"New York","country_code":"US","name":"E2E Admission Hall","state_code":"NY","state_name":"New York","zip_code":"10001"}'::jsonb,
    0, 'ch_e2e_payment_return_confirmed', 2500, 2500, 0
);

insert into event_purchase (
    event_purchase_id,
    admission_offer_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    payment_provider_id,
    provider_checkout_session_id,
    provider_checkout_url,
    status,
    ticket_title,
    user_id,

    charge_model,
    connected_seller_id,
    provider_object_account_id,
    seller_snapshot,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    venue_snapshot
)
values (
    '59555555-5555-5555-5555-655555555914',
    '59555555-5555-5555-5555-655555555914',
    4500,
    'USD',
    0,
    '55555555-5555-5555-5555-555555555914',
    '56555555-5555-5555-5555-755555555914',
    current_timestamp + interval '5 days',
    'stripe',
    'cs_e2e_invitation_request_checkout',
    'https://example.test/checkout/invitation-request',
    'pending',
    'VIP allocation',
    '77777777-7777-7777-7777-777777777704',

    'direct-charge', 'acct_e2e_alpha', 'acct_e2e_alpha',
    '{"connected_account_id":"acct_e2e_alpha","display_name":"E2E Alpha Fiscal Sponsor","provider":"stripe"}'::jsonb,
    'inclusive', 'manual', 'professional-event-admission',
    '{"address":"123 Payment Way","city":"New York","country_code":"US","name":"E2E Admission Hall","state_code":"NY","state_name":"New York","zip_code":"10001"}'::jsonb
), (
    '59555555-5555-5555-5555-555555555916',
    '59555555-5555-5555-5555-555555555916',
    4000,
    'USD',
    0,
    '55555555-5555-5555-5555-555555555916',
    '56555555-5555-5555-5555-555555555916',
    current_timestamp + interval '5 days',
    'stripe',
    'cs_e2e_paid_offer_checkout',
    'https://example.test/checkout/paid-offer',
    'pending',
    'Private paid offer',
    '77777777-7777-7777-7777-777777777708',

    'direct-charge', 'acct_e2e_alpha', 'acct_e2e_alpha',
    '{"connected_account_id":"acct_e2e_alpha","display_name":"E2E Alpha Fiscal Sponsor","provider":"stripe"}'::jsonb,
    'inclusive', 'manual', 'professional-event-admission',
    '{"address":"123 Payment Way","city":"New York","country_code":"US","name":"E2E Admission Hall","state_code":"NY","state_name":"New York","zip_code":"10001"}'::jsonb
);

insert into event_purchase (
    event_purchase_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    payment_provider_id,
    provider_checkout_session_id,
    provider_checkout_url,
    status,
    ticket_title,
    user_id,

    charge_model,
    connected_seller_id,
    provider_object_account_id,
    seller_snapshot,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    venue_snapshot
)
values (
    '59555555-5555-5555-5555-655555555912',
    2500,
    'USD',
    0,
    '55555555-5555-5555-5555-555555555912',
    '56555555-5555-5555-5555-555555555912',
    current_timestamp + interval '5 days',
    'stripe',
    'cs_e2e_payment_return_pending',
    'https://example.test/checkout/payment-return',
    'pending',
    'Payment return pass',
    '77777777-7777-7777-7777-777777777708',

    'direct-charge', 'acct_e2e_alpha', 'acct_e2e_alpha',
    '{"connected_account_id":"acct_e2e_alpha","display_name":"E2E Alpha Fiscal Sponsor","provider":"stripe"}'::jsonb,
    'inclusive', 'manual', 'professional-event-admission',
    '{"address":"123 Payment Way","city":"New York","country_code":"US","name":"E2E Admission Hall","state_code":"NY","state_name":"New York","zip_code":"10001"}'::jsonb
);

insert into event_purchase (
    event_purchase_id,
    amount_minor,
    completed_at,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    payment_provider_id,
    provider_checkout_session_id,
    provider_checkout_url,
    provider_payment_reference,
    refunded_at,
    status,
    ticket_title,
    user_id,

    charge_model,
    connected_seller_id,
    provider_object_account_id,
    seller_snapshot,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    venue_snapshot,
    final_platform_fee_amount_minor,
    provider_charge_id,
    provider_total_minor,
    subtotal_excluding_tax_minor,
    tax_amount_minor
)
values (
    '59555555-5555-5555-5555-555555555920',
    3000,
    current_timestamp - interval '5 days',
    'USD',
    0,
    '55555555-5555-5555-5555-555555555920',
    '56555555-5555-5555-5555-555555555920',
    'stripe',
    'cs_e2e_refunded_capacity',
    'https://checkout.stripe.test/cs_e2e_refunded_capacity',
    'pi_e2e_refunded_capacity',
    current_timestamp - interval '1 day',
    'refunded',
    'Refunded conference pass',
    '77777777-7777-7777-7777-777777777702',

    'direct-charge', 'acct_e2e_alpha', 'acct_e2e_alpha',
    '{"connected_account_id":"acct_e2e_alpha","display_name":"E2E Alpha Fiscal Sponsor","provider":"stripe"}'::jsonb,
    'inclusive', 'manual', 'professional-event-admission',
    '{"address":"123 Payment Way","city":"New York","country_code":"US","name":"E2E Admission Hall","state_code":"NY","state_name":"New York","zip_code":"10001"}'::jsonb,
    0, 'ch_e2e_refunded_capacity', 3000, 3000, 0
);

insert into event_purchase (
    event_purchase_id,
    amount_minor,
    completed_at,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    payment_provider_id,
    provider_checkout_session_id,
    provider_checkout_url,
    provider_payment_reference,
    status,
    ticket_title,
    user_id,

    charge_model,
    connected_seller_id,
    provider_object_account_id,
    seller_snapshot,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    venue_snapshot,
    final_platform_fee_amount_minor,
    provider_charge_id,
    provider_total_minor,
    subtotal_excluding_tax_minor,
    tax_amount_minor
)
values (
    '59555555-5555-5555-5555-555555555531',
    5000,
    current_timestamp - interval '1 day',
    'USD',
    0,
    '55555555-5555-5555-5555-555555555523',
    '56555555-5555-5555-5555-555555555523',
    'stripe',
    'cs_e2e_refund_action_available',
    'https://checkout.stripe.test/cs_e2e_refund_action_available',
    'pi_e2e_refund_action_available',
    'completed',
    'VIP pass',
    '77777777-7777-7777-7777-777777777703',

    'direct-charge', 'acct_e2e_alpha', 'acct_e2e_alpha',
    '{"connected_account_id":"acct_e2e_alpha","display_name":"E2E Alpha Fiscal Sponsor","provider":"stripe"}'::jsonb,
    'inclusive', 'manual', 'professional-event-admission',
    '{"address":"123 Payment Way","city":"New York","country_code":"US","name":"E2E Admission Hall","state_code":"NY","state_name":"New York","zip_code":"10001"}'::jsonb,
    0, 'ch_e2e_refund_action_available', 5000, 5000, 0
);

-- Confirmed attendees own capacity through completed zero-value purchases
insert into event_purchase (
    amount_minor,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id
)
select
    0,
    null,
    0,
    ea.event_id,
    ett.event_ticket_type_id,
    'completed',
    ett.title,
    ea.user_id
from event_attendee ea
join lateral (
    select ett.event_ticket_type_id, ett.title
    from event_ticket_type ett
    where ett.event_id = ea.event_id
    order by ett."order", ett.event_ticket_type_id
    limit 1
) ett on true
where ea.status = 'confirmed'
and not exists (
    select 1
    from event_purchase ep
    where ep.event_id = ea.event_id
    and ep.user_id = ea.user_id
    and (
        ep.status in (
            'completed',
            'refund-pending',
            'refund-recovery-pending',
            'refund-requested'
        )
        or (
            ep.status = 'pending'
            and ep.hold_expires_at > current_timestamp
        )
    )
);

-- ============================================================================
-- EVENT REFUND REQUESTS
-- ============================================================================

-- Refund requests used by attendee and organizer review coverage.
insert into event_refund_request (
    event_refund_request_id,
    event_purchase_id,
    requested_by_user_id,
    status,

    requested_reason,
    review_note,
    reviewed_at,
    reviewed_by_user_id
)
values (
    '60555555-5555-5555-5555-555555555521',
    '59555555-5555-5555-5555-555555555521',
    '77777777-7777-7777-7777-777777777705',
    'pending',

    'Need to cancel',
    null,
    null,
    null
), (
    '60555555-5555-5555-5555-555555555522',
    '59555555-5555-5555-5555-555555555522',
    '77777777-7777-7777-7777-777777777706',
    'approving',

    'Schedule conflict',
    'Approved by the organizer',
    now() - interval '2 days',
    '77777777-7777-7777-7777-777777777701'
), (
    '60555555-5555-5555-5555-555555555523',
    '59555555-5555-5555-5555-555555555523',
    '77777777-7777-7777-7777-777777777707',
    'rejected',

    'Need a different date',
    'The request falls outside the refund policy window.',
    now() - interval '3 days',
    '77777777-7777-7777-7777-777777777701'
), (
    '60555555-5555-5555-5555-555555555524',
    '59555555-5555-5555-5555-555555555525',
    '77777777-7777-7777-7777-777777777712',
    'approved',

    'Refund completed',
    'Approved by the organizer',
    now() - interval '4 days',
    '77777777-7777-7777-7777-777777777701'
), (
    '60555555-5555-5555-5555-555555555529',
    '59555555-5555-5555-5555-555555555529',
    '77777777-7777-7777-7777-777777777709',
    'pending',

    'Duplicate registration',
    null,
    null,
    null
), (
    '60555555-5555-5555-5555-555555555530',
    '59555555-5555-5555-5555-555555555530',
    '77777777-7777-7777-7777-777777777710',
    'approving',

    'Provider completed the refund outside OCG',
    'Approved by the organizer',
    now() - interval '10 days',
    '77777777-7777-7777-7777-777777777701'
);

-- Durable refund jobs used by recovery and operational state coverage.
insert into payment_job (
    attempt_count,
    completed_at,
    event_purchase_id,
    failure_message,
    idempotency_key,
    kind,
    next_attempt_at,
    payment_job_id,
    payment_provider_id,
    status
)
values (
    1,
    null,
    '59555555-5555-5555-5555-555555555522',
    'Provider refund requires manual recovery',
    'event-purchase-refund-59555555-5555-5555-5555-555555555522',
    'event-purchase-refund',
    now() + interval '100 years',
    '64555555-5555-5555-5555-555555555522',
    'stripe',
    'failed'
), (
    1,
    null,
    '59555555-5555-5555-5555-555555555526',
    null,
    'event-purchase-refund-59555555-5555-5555-5555-555555555526',
    'event-purchase-refund',
    now() + interval '100 years',
    '64555555-5555-5555-5555-555555555526',
    'stripe',
    'pending'
), (
    10,
    null,
    '59555555-5555-5555-5555-555555555527',
    'Provider refund attempts exhausted',
    'event-purchase-refund-59555555-5555-5555-5555-555555555527',
    'event-purchase-refund',
    now() + interval '100 years',
    '64555555-5555-5555-5555-555555555527',
    'stripe',
    'failed'
), (
    1,
    now() - interval '1 day',
    '59555555-5555-5555-5555-555555555528',
    null,
    'event-purchase-refund-59555555-5555-5555-5555-555555555528',
    'event-purchase-refund',
    now() + interval '100 years',
    '64555555-5555-5555-5555-555555555528',
    'stripe',
    'completed'
), (
    1,
    null,
    '59555555-5555-5555-5555-555555555530',
    'Provider refund requires external recovery',
    'event-purchase-refund-59555555-5555-5555-5555-555555555530',
    'event-purchase-refund',
    now() + interval '100 years',
    '64555555-5555-5555-5555-555555555530',
    'stripe',
    'failed'
);

-- Durable refunds used by recovery and operational state coverage.
insert into event_purchase_refund (
    amount_minor,
    currency_code,
    event_purchase_id,
    event_purchase_refund_id,
    kind,
    payment_job_id,
    payment_provider_id,
    status,
    terminal_failure,

    event_refund_request_id,
    finalized_at,
    provider_refund_id
)
values (
    5000,
    'USD',
    '59555555-5555-5555-5555-555555555522',
    '61555555-5555-5555-5555-555555555522',
    'refund-request-approval',
    '64555555-5555-5555-5555-555555555522',
    'stripe',
    'provider-failed',
    true,

    '60555555-5555-5555-5555-555555555522',
    null,
    're_e2e_refund_recovery'
), (
    5000,
    'USD',
    '59555555-5555-5555-5555-555555555526',
    '61555555-5555-5555-5555-555555555526',
    'event-cancellation',
    '64555555-5555-5555-5555-555555555526',
    'stripe',
    'provider-pending',
    false,

    null,
    null,
    're_e2e_refund_processing'
), (
    5000,
    'USD',
    '59555555-5555-5555-5555-555555555527',
    '61555555-5555-5555-5555-555555555527',
    'event-cancellation',
    '64555555-5555-5555-5555-555555555527',
    'stripe',
    'provider-failed',
    false,

    null,
    null,
    null
), (
    5000,
    'USD',
    '59555555-5555-5555-5555-555555555528',
    '61555555-5555-5555-5555-555555555528',
    'event-cancellation',
    '64555555-5555-5555-5555-555555555528',
    'stripe',
    'finalized',
    false,

    null,
    now() - interval '1 day',
    're_e2e_refund_finalized'
), (
    5000,
    'USD',
    '59555555-5555-5555-5555-555555555530',
    '61555555-5555-5555-5555-555555555530',
    'refund-request-approval',
    '64555555-5555-5555-5555-555555555530',
    'stripe',
    'provider-failed',
    true,

    '60555555-5555-5555-5555-555555555530',
    null,
    're_e2e_refund_recovery_durable'
);

-- Exhausted application-fee adjustment shown in the financial recovery queue.
insert into payment_job (
    attempt_count,
    event_purchase_id,
    failure_message,
    idempotency_key,
    kind,
    next_attempt_at,
    payment_job_id,
    payment_provider_id,
    status,
    updated_at
)
values (
    10,
    '59555555-5555-5555-5555-555555555526',
    'Application fee refund attempts exhausted',
    'event-purchase-application-fee-adjustment-e2e-recovery',
    'event-purchase-application-fee-adjustment',
    now() + interval '100 years',
    '64555555-5555-5555-5555-555555555531',
    'stripe',
    'failed',
    now() - interval '20 days'
);

-- Exhausted application-fee adjustment shown in the financial recovery queue.
insert into event_purchase_application_fee_adjustment (
    amount_minor,
    event_purchase_application_fee_adjustment_id,
    event_purchase_id,
    kind,
    payment_job_id,
    updated_at
)
values (
    500,
    '63555555-5555-5555-5555-555555555526',
    '59555555-5555-5555-5555-555555555526',
    'purchase-refund',
    '64555555-5555-5555-5555-555555555531',
    now() - interval '20 days'
);

-- Credit note lifecycle jobs shown in the attendee purchase documents.
insert into payment_job (
    attempt_count,
    completed_at,
    event_purchase_id,
    idempotency_key,
    kind,
    next_attempt_at,
    payment_job_id,
    payment_provider_id,
    status,
    updated_at
)
values (
    1,
    null,
    '59555555-5555-5555-5555-555555555526',
    'event-purchase-credit-note-e2e-processing',
    'event-purchase-credit-note',
    now() + interval '1 hour',
    '64555555-5555-5555-5555-555555555532',
    'stripe',
    'pending',
    now() - interval '1 hour'
), (
    1,
    now() - interval '1 day',
    '59555555-5555-5555-5555-555555555528',
    'event-purchase-credit-note-e2e-issued',
    'event-purchase-credit-note',
    now() + interval '100 years',
    '64555555-5555-5555-5555-555555555533',
    'stripe',
    'completed',
    now() - interval '1 day'
);

-- Credit note lifecycle states shown in the attendee purchase documents.
insert into event_purchase_credit_note (
    amount_minor,
    currency_code,
    event_purchase_credit_note_id,
    event_purchase_refund_id,
    payment_job_id,
    payment_provider_id,
    provider_object_account_id,
    tax_amount_minor,
    updated_at,

    provider_credit_note_id,
    provider_hosted_url,
    provider_pdf_url
)
values (
    5000,
    'USD',
    '62555555-5555-5555-5555-555555555526',
    '61555555-5555-5555-5555-555555555526',
    '64555555-5555-5555-5555-555555555532',
    'stripe',
    'acct_e2e_alpha',
    0,
    now() - interval '1 hour',

    null,
    null,
    null
), (
    5000,
    'USD',
    '62555555-5555-5555-5555-555555555528',
    '61555555-5555-5555-5555-555555555528',
    '64555555-5555-5555-5555-555555555533',
    'stripe',
    'acct_e2e_alpha',
    0,
    now() - interval '1 day',

    'cn_e2e_refund_finalized',
    'https://documents.stripe.test/cn_e2e_refund_finalized',
    'https://documents.stripe.test/cn_e2e_refund_finalized.pdf'
);

-- Exhausted credit-note job shown in the financial recovery queue.
insert into payment_job (
    attempt_count,
    event_purchase_id,
    failure_message,
    idempotency_key,
    kind,
    next_attempt_at,
    payment_job_id,
    payment_provider_id,
    status,
    updated_at
)
values (
    10,
    '59555555-5555-5555-5555-555555555527',
    'Credit note attempts exhausted',
    'event-purchase-credit-note-e2e-recovery',
    'event-purchase-credit-note',
    now() + interval '100 years',
    '64555555-5555-5555-5555-555555555534',
    'stripe',
    'failed',
    now() - interval '21 days'
);

-- Exhausted credit note shown in the financial recovery queue.
insert into event_purchase_credit_note (
    amount_minor,
    currency_code,
    event_purchase_credit_note_id,
    event_purchase_refund_id,
    payment_job_id,
    payment_provider_id,
    provider_object_account_id,
    tax_amount_minor,
    updated_at
)
values (
    5000,
    'USD',
    '62555555-5555-5555-5555-555555555527',
    '61555555-5555-5555-5555-555555555527',
    '64555555-5555-5555-5555-555555555534',
    'stripe',
    'acct_e2e_alpha',
    0,
    now() - interval '21 days'
);

-- Stripe webhook fixtures (ticket types are defined in 60_enrollment.sql)

-- Price windows make the Stripe webhook ticket types available to attendees.
insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id,
    starts_at,
    ends_at
)
values (
    '57555555-5555-5555-5555-555555555940',
    2500,
    '56555555-5555-5555-5555-555555555940',
    null,
    null
), (
    '57555555-5555-5555-5555-555555555941',
    3000,
    '56555555-5555-5555-5555-555555555941',
    null,
    null
), (
    '57555555-5555-5555-5555-555555555942',
    5000,
    '56555555-5555-5555-5555-555555555942',
    null,
    null
);

-- Purchases used by the Stripe checkout expiration, invoice, and refund webhooks.
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    completed_at,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    payment_provider_id,
    provider_checkout_session_id,
    provider_checkout_url,
    provider_payment_reference,
    status,
    ticket_title,
    user_id,

    charge_model,
    connected_seller_id,
    provider_object_account_id,
    seller_snapshot,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    venue_snapshot,
    final_platform_fee_amount_minor,
    provider_charge_id,
    provider_invoice_id,
    provider_total_minor,
    subtotal_excluding_tax_minor,
    tax_amount_minor
)
values (
    '59555555-5555-5555-5555-555555555940',
    2500,
    now() - interval '1 day',
    'USD',
    0,
    '55555555-5555-5555-5555-555555555940',
    '56555555-5555-5555-5555-555555555940',
    'stripe',
    'cs_e2e_webhook_expire_paid',
    'https://checkout.stripe.test/cs_e2e_webhook_expire_paid',
    'pi_e2e_webhook_expire_paid',
    'completed',
    'Webhook expiration pass',
    '77777777-7777-7777-7777-777777777705',

    'direct-charge', 'acct_e2e_alpha', 'acct_e2e_alpha',
    '{"connected_account_id":"acct_e2e_alpha","display_name":"E2E Alpha Fiscal Sponsor","provider":"stripe"}'::jsonb,
    'inclusive', 'manual', 'professional-event-admission',
    '{"address":"123 Payment Way","city":"New York","country_code":"US","name":"E2E Admission Hall","state_code":"NY","state_name":"New York","zip_code":"10001"}'::jsonb,
    0, 'ch_e2e_webhook_expire_paid', null, 2500, 2500, 0
), (
    '59555555-5555-5555-5555-555555555942',
    3000,
    now() - interval '1 day',
    'USD',
    0,
    '55555555-5555-5555-5555-555555555941',
    '56555555-5555-5555-5555-555555555941',
    'stripe',
    'cs_e2e_webhook_invoice',
    'https://checkout.stripe.test/cs_e2e_webhook_invoice',
    'pi_e2e_webhook_invoice',
    'completed',
    'Webhook invoice pass',
    '77777777-7777-7777-7777-777777777708',

    'direct-charge', 'acct_e2e_alpha', 'acct_e2e_alpha',
    '{"connected_account_id":"acct_e2e_alpha","display_name":"E2E Alpha Fiscal Sponsor","provider":"stripe"}'::jsonb,
    'inclusive', 'manual', 'professional-event-admission',
    '{"address":"123 Payment Way","city":"New York","country_code":"US","name":"E2E Admission Hall","state_code":"NY","state_name":"New York","zip_code":"10001"}'::jsonb,
    0, 'ch_e2e_webhook_invoice', null, 3000, 3000, 0
), (
    '59555555-5555-5555-5555-555555555943',
    5000,
    now() - interval '1 day',
    'USD',
    0,
    '55555555-5555-5555-5555-555555555942',
    '56555555-5555-5555-5555-555555555942',
    'stripe',
    'cs_e2e_webhook_refund',
    'https://checkout.stripe.test/cs_e2e_webhook_refund',
    'pi_e2e_webhook_refund',
    'refund-pending',
    'Webhook refund pass',
    '77777777-7777-7777-7777-777777777706',

    'direct-charge', 'acct_e2e_alpha', 'acct_e2e_alpha',
    '{"connected_account_id":"acct_e2e_alpha","display_name":"E2E Alpha Fiscal Sponsor","provider":"stripe"}'::jsonb,
    'inclusive', 'manual', 'professional-event-admission',
    '{"address":"123 Payment Way","city":"New York","country_code":"US","name":"E2E Admission Hall","state_code":"NY","state_name":"New York","zip_code":"10001"}'::jsonb,
    0, 'ch_e2e_webhook_refund', null, 5000, 5000, 0
);

-- Pending checkout purchase that fills the second expiration webhook seat.
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    payment_provider_id,
    provider_checkout_session_id,
    provider_checkout_url,
    status,
    ticket_title,
    user_id,

    charge_model,
    connected_seller_id,
    provider_object_account_id,
    seller_snapshot,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    venue_snapshot
)
values (
    '59555555-5555-5555-5555-555555555941',
    2500,
    'USD',
    0,
    '55555555-5555-5555-5555-555555555940',
    '56555555-5555-5555-5555-555555555940',
    now() + interval '2 days',
    'stripe',
    'cs_e2e_webhook_expire',
    'https://checkout.stripe.test/cs_e2e_webhook_expire',
    'pending',
    'Webhook expiration pass',
    '77777777-7777-7777-7777-777777777707',

    'direct-charge', 'acct_e2e_alpha', 'acct_e2e_alpha',
    '{"connected_account_id":"acct_e2e_alpha","display_name":"E2E Alpha Fiscal Sponsor","provider":"stripe"}'::jsonb,
    'inclusive', 'manual', 'professional-event-admission',
    '{"address":"123 Payment Way","city":"New York","country_code":"US","name":"E2E Admission Hall","state_code":"NY","state_name":"New York","zip_code":"10001"}'::jsonb
);

-- Confirmed attendee whose access is canceled after the refund webhook finalizes.
insert into event_attendee (
    event_id,
    user_id
)
values (
    '55555555-5555-5555-5555-555555555942',
    '77777777-7777-7777-7777-777777777706'
);

-- Approved refund request linked to the Stripe refund webhook fixture.
insert into event_refund_request (
    event_refund_request_id,
    event_purchase_id,
    requested_by_user_id,
    status,

    requested_reason,
    review_note,
    reviewed_at,
    reviewed_by_user_id
)
values (
    '60555555-5555-5555-5555-555555555940',
    '59555555-5555-5555-5555-555555555943',
    '77777777-7777-7777-7777-777777777706',
    'approving',

    'Need Stripe webhook coverage',
    'Approved for webhook finalization.',
    now() - interval '1 day',
    '77777777-7777-7777-7777-777777777703'
);

-- Refund job held far in the future until the Stripe webhook confirms provider success.
insert into payment_job (
    attempt_count,
    event_purchase_id,
    failure_message,
    idempotency_key,
    kind,
    next_attempt_at,
    payment_job_id,
    payment_provider_id,
    status
)
values (
    0,
    '59555555-5555-5555-5555-555555555943',
    null,
    'event-purchase-refund-59555555-5555-5555-5555-555555555943',
    'event-purchase-refund',
    now() + interval '1 year',
    '64555555-5555-5555-5555-555555555940',
    'stripe',
    'pending'
);

-- Durable refund updated by the Stripe refund webhook before worker finalization.
insert into event_purchase_refund (
    amount_minor,
    currency_code,
    event_purchase_id,
    event_purchase_refund_id,
    kind,
    payment_job_id,
    payment_provider_id,
    status,
    terminal_failure,

    event_refund_request_id,
    finalized_at,
    initiated_by_user_id,
    provider_refund_id,
    provider_refunded_at,
    review_note
)
values (
    5000,
    'USD',
    '59555555-5555-5555-5555-555555555943',
    '61555555-5555-5555-5555-555555555940',
    'refund-request-approval',
    '64555555-5555-5555-5555-555555555940',
    'stripe',
    'provider-pending',
    false,

    '60555555-5555-5555-5555-555555555940',
    null,
    '77777777-7777-7777-7777-777777777703',
    're_e2e_webhook',
    null,
    'Approved for webhook finalization.'
);
