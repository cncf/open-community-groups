-- Tests matching provider validation snapshots against payment recipients.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(10);

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Recipients and the snapshots validated against them
create temporary table test_snapshot (
    expected_recipient jsonb not null,
    null_recipients_snapshot jsonb not null,
    snapshot jsonb not null,
    validated_recipient jsonb not null
);
insert into test_snapshot values (
    '{"provider": "stripe", "recipient_id": "acct_previous"}'::jsonb,
    '{
        "expected_payment_recipient": null,
        "require_automatic_tax": false,
        "validated_payment_recipient": null
    }'::jsonb,
    '{
        "expected_payment_recipient": {"provider": "stripe", "recipient_id": "acct_previous"},
        "require_automatic_tax": true,
        "validated_payment_recipient": {"provider": "stripe", "recipient_id": "acct_new"}
    }'::jsonb,
    '{"provider": "stripe", "recipient_id": "acct_new"}'::jsonb
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should match a snapshot taken for the expected and validated recipients
select is(
    (
        select payment_validation_snapshot_matches(snapshot, expected_recipient, validated_recipient)
        from test_snapshot
    ),
    true,
    'Should match a snapshot taken for the expected and validated recipients'
);

-- Should match SQL null recipients against JSON null snapshot recipients
select is(
    (
        select payment_validation_snapshot_matches(null_recipients_snapshot, null, null)
        from test_snapshot
    ),
    true,
    'Should match SQL null recipients against JSON null snapshot recipients'
);

-- Should not match a missing snapshot
select is(
    (
        select payment_validation_snapshot_matches(null, expected_recipient, validated_recipient)
        from test_snapshot
    ),
    false,
    'Should not match a missing snapshot'
);

-- Should not match a recipient against a JSON null snapshot recipient
select is(
    (
        select payment_validation_snapshot_matches(null_recipients_snapshot, expected_recipient, null)
        from test_snapshot
    ),
    false,
    'Should not match a recipient against a JSON null snapshot recipient'
);

-- Should not match a snapshot missing the automatic-tax requirement
select is(
    (
        select payment_validation_snapshot_matches(snapshot - 'require_automatic_tax', expected_recipient, validated_recipient)
        from test_snapshot
    ),
    false,
    'Should not match a snapshot missing the automatic-tax requirement'
);

-- Should not match a snapshot missing the expected recipient
select is(
    (
        select payment_validation_snapshot_matches(snapshot - 'expected_payment_recipient', expected_recipient, validated_recipient)
        from test_snapshot
    ),
    false,
    'Should not match a snapshot missing the expected recipient'
);

-- Should not match a snapshot missing the validated recipient
select is(
    (
        select payment_validation_snapshot_matches(snapshot - 'validated_payment_recipient', expected_recipient, validated_recipient)
        from test_snapshot
    ),
    false,
    'Should not match a snapshot missing the validated recipient'
);

-- Should not match a snapshot taken for another expected recipient
select is(
    (
        select payment_validation_snapshot_matches(snapshot, validated_recipient, validated_recipient)
        from test_snapshot
    ),
    false,
    'Should not match a snapshot taken for another expected recipient'
);

-- Should not match a snapshot taken for another validated recipient
select is(
    (
        select payment_validation_snapshot_matches(snapshot, expected_recipient, expected_recipient)
        from test_snapshot
    ),
    false,
    'Should not match a snapshot taken for another validated recipient'
);

-- Should not match a SQL null recipient against a snapshot recipient
select is(
    (
        select payment_validation_snapshot_matches(snapshot, null, validated_recipient)
        from test_snapshot
    ),
    false,
    'Should not match a SQL null recipient against a snapshot recipient'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
