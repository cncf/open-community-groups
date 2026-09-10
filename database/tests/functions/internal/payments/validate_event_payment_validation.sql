-- Tests binding an event payload's provider validation snapshot to the locked group state.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(10);

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Recipient protected by the group lock and the snapshots validated against it
create temporary table test_binding (recipient jsonb not null, automatic_snapshot jsonb not null, manual_snapshot jsonb not null);
insert into test_binding values (
    '{"provider": "stripe", "recipient_id": "acct_123"}'::jsonb,
    '{
        "expected_payment_recipient": {"provider": "stripe", "recipient_id": "acct_123"},
        "require_automatic_tax": true,
        "validated_payment_recipient": {"provider": "stripe", "recipient_id": "acct_123"}
    }'::jsonb,
    '{
        "expected_payment_recipient": {"provider": "stripe", "recipient_id": "acct_123"},
        "manual_tax_rate_ids": ["txr_state"],
        "require_automatic_tax": false,
        "tax_behavior": "exclusive",
        "tax_calculation_mode": "manual",
        "validated_payment_recipient": {"provider": "stripe", "recipient_id": "acct_123"}
    }'::jsonb
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept a matching automatic-tax snapshot
select lives_ok(
    $$select validate_event_payment_validation(
        (select jsonb_build_object('_payment_validation', automatic_snapshot, 'tax_calculation_mode', 'automatic') from test_binding),
        (select recipient from test_binding),
        '{}'::text[],
        'inclusive',
        'automatic'
    )$$,
    'Should accept a matching automatic-tax snapshot'
);

-- Should accept a matching manual-tax snapshot
select lives_ok(
    $$select validate_event_payment_validation(
        (select jsonb_build_object('_payment_validation', manual_snapshot, 'tax_calculation_mode', 'manual') from test_binding),
        (select recipient from test_binding),
        array['txr_state']::text[],
        'exclusive',
        'manual'
    )$$,
    'Should accept a matching manual-tax snapshot'
);

-- Should reject a snapshot whose tax mode is not manual for a manual payload
select throws_ok(
    $$select validate_event_payment_validation(
        (select jsonb_build_object('_payment_validation', manual_snapshot || '{"tax_calculation_mode": "automatic"}'::jsonb, 'tax_calculation_mode', 'manual') from test_binding),
        (select recipient from test_binding),
        array['txr_state']::text[],
        'exclusive',
        'manual'
    )$$,
    'OCG01',
    'payment configuration changed during provider validation',
    'Should reject a snapshot whose tax mode is not manual for a manual payload'
);

-- Should reject a payload without a snapshot
select throws_ok(
    $$select validate_event_payment_validation(
        '{"tax_calculation_mode": "automatic"}'::jsonb,
        (select recipient from test_binding),
        '{}'::text[],
        'inclusive',
        'automatic'
    )$$,
    'OCG01',
    'payment configuration changed during provider validation',
    'Should reject a payload without a snapshot'
);

-- Should reject a snapshot missing the validated recipient
select throws_ok(
    $$select validate_event_payment_validation(
        (select jsonb_build_object('_payment_validation', automatic_snapshot - 'validated_payment_recipient', 'tax_calculation_mode', 'automatic') from test_binding),
        (select recipient from test_binding),
        '{}'::text[],
        'inclusive',
        'automatic'
    )$$,
    'OCG01',
    'payment configuration changed during provider validation',
    'Should reject a snapshot missing the validated recipient'
);

-- Should reject a snapshot taken for another recipient
select throws_ok(
    $$select validate_event_payment_validation(
        (select jsonb_build_object('_payment_validation', automatic_snapshot, 'tax_calculation_mode', 'automatic') from test_binding),
        '{"provider": "stripe", "recipient_id": "acct_456"}'::jsonb,
        '{}'::text[],
        'inclusive',
        'automatic'
    )$$,
    'OCG01',
    'payment configuration changed during provider validation',
    'Should reject a snapshot taken for another recipient'
);

-- Should reject an automatic-tax payload validated without automatic tax
select throws_ok(
    $$select validate_event_payment_validation(
        (select jsonb_build_object('_payment_validation', manual_snapshot, 'tax_calculation_mode', 'automatic') from test_binding),
        (select recipient from test_binding),
        '{}'::text[],
        'inclusive',
        'automatic'
    )$$,
    'OCG01',
    'payment configuration changed during provider validation',
    'Should reject an automatic-tax payload validated without automatic tax'
);

-- Should reject a payload omitting the tax mode when the snapshot lacks automatic tax
select throws_ok(
    $$select validate_event_payment_validation(
        (select jsonb_build_object('_payment_validation', manual_snapshot) from test_binding),
        (select recipient from test_binding),
        array['txr_state']::text[],
        'exclusive',
        'manual'
    )$$,
    'OCG01',
    'payment configuration changed during provider validation',
    'Should reject a payload omitting the tax mode when the snapshot lacks automatic tax'
);

-- Should reject manual tax rates that differ from the snapshot
select throws_ok(
    $$select validate_event_payment_validation(
        (select jsonb_build_object('_payment_validation', manual_snapshot, 'tax_calculation_mode', 'manual') from test_binding),
        (select recipient from test_binding),
        array['txr_county']::text[],
        'exclusive',
        'manual'
    )$$,
    'OCG01',
    'payment configuration changed during provider validation',
    'Should reject manual tax rates that differ from the snapshot'
);

-- Should reject a tax behavior that differs from the snapshot
select throws_ok(
    $$select validate_event_payment_validation(
        (select jsonb_build_object('_payment_validation', manual_snapshot, 'tax_calculation_mode', 'manual') from test_binding),
        (select recipient from test_binding),
        array['txr_state']::text[],
        'inclusive',
        'manual'
    )$$,
    'OCG01',
    'payment configuration changed during provider validation',
    'Should reject a tax behavior that differs from the snapshot'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
