-- Tests classifying the refund workflow progress of a purchase.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(16);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should classify a canceled event's live checkout hold as awaiting checkout
select is(
    event_purchase_refund_progress(
        jsonb_populate_record(null::event_purchase, jsonb_build_object(
            'hold_expires_at', current_timestamp + interval '10 minutes',
            'status', 'pending'
        )),
        true,
        null::event_purchase_refund,
        null::payment_job
    ),
    'awaiting-checkout',
    'Should classify a canceled event''s live checkout hold as awaiting checkout'
);

-- Should classify a canceled event's pending checkout with a session as awaiting checkout
select is(
    event_purchase_refund_progress(
        jsonb_populate_record(null::event_purchase, jsonb_build_object(
            'hold_expires_at', current_timestamp - interval '10 minutes',
            'provider_checkout_session_id', 'cs_refund_progress',
            'status', 'pending'
        )),
        true,
        null::event_purchase_refund,
        null::payment_job
    ),
    'awaiting-checkout',
    'Should classify a canceled event''s pending checkout with a session as awaiting checkout'
);

-- Should classify a failed job as queued
select is(
    event_purchase_refund_progress(
        jsonb_populate_record(null::event_purchase, '{"status": "refund-pending"}'::jsonb),
        false,
        jsonb_populate_record(null::event_purchase_refund, '{"status": "provider-pending", "terminal_failure": false}'::jsonb),
        jsonb_populate_record(null::payment_job, '{"attempt_count": 1, "status": "failed"}'::jsonb)
    ),
    'queued',
    'Should classify a failed job as queued'
);

-- Should classify a finalized refund as refunded
select is(
    event_purchase_refund_progress(
        jsonb_populate_record(null::event_purchase, '{"status": "refund-pending"}'::jsonb),
        false,
        jsonb_populate_record(null::event_purchase_refund, '{"status": "finalized", "terminal_failure": false}'::jsonb),
        jsonb_populate_record(null::payment_job, '{"attempt_count": 1, "status": "completed"}'::jsonb)
    ),
    'refunded',
    'Should classify a finalized refund as refunded'
);

-- Should classify a pending job as queued
select is(
    event_purchase_refund_progress(
        jsonb_populate_record(null::event_purchase, '{"status": "refund-pending"}'::jsonb),
        false,
        jsonb_populate_record(null::event_purchase_refund, '{"status": "provider-pending", "terminal_failure": false}'::jsonb),
        jsonb_populate_record(null::payment_job, '{"attempt_count": 0, "status": "pending"}'::jsonb)
    ),
    'queued',
    'Should classify a pending job as queued'
);

-- Should classify a processing job as processing
select is(
    event_purchase_refund_progress(
        jsonb_populate_record(null::event_purchase, '{"status": "refund-pending"}'::jsonb),
        false,
        jsonb_populate_record(null::event_purchase_refund, '{"status": "provider-pending", "terminal_failure": false}'::jsonb),
        jsonb_populate_record(null::payment_job, '{"attempt_count": 1, "status": "processing"}'::jsonb)
    ),
    'processing',
    'Should classify a processing job as processing'
);

-- Should classify a provider-succeeded refund as processing
select is(
    event_purchase_refund_progress(
        jsonb_populate_record(null::event_purchase, '{"status": "refund-pending"}'::jsonb),
        false,
        jsonb_populate_record(null::event_purchase_refund, '{"status": "provider-succeeded", "terminal_failure": false}'::jsonb),
        jsonb_populate_record(null::payment_job, '{"attempt_count": 1, "status": "pending"}'::jsonb)
    ),
    'processing',
    'Should classify a provider-succeeded refund as processing'
);

-- Should classify a purchase awaiting recovery as recovery required
select is(
    event_purchase_refund_progress(
        jsonb_populate_record(null::event_purchase, '{"status": "refund-recovery-pending"}'::jsonb),
        false,
        jsonb_populate_record(null::event_purchase_refund, '{"status": "provider-pending", "terminal_failure": false}'::jsonb),
        jsonb_populate_record(null::payment_job, '{"attempt_count": 1, "status": "pending"}'::jsonb)
    ),
    'recovery-required',
    'Should classify a purchase awaiting recovery as recovery required'
);

-- Should classify a refund with a provider reference as processing
select is(
    event_purchase_refund_progress(
        jsonb_populate_record(null::event_purchase, '{"status": "refund-pending"}'::jsonb),
        false,
        jsonb_populate_record(null::event_purchase_refund, '{"provider_refund_id": "re_refund_progress", "status": "provider-pending", "terminal_failure": false}'::jsonb),
        jsonb_populate_record(null::payment_job, '{"attempt_count": 1, "status": "pending"}'::jsonb)
    ),
    'processing',
    'Should classify a refund with a provider reference as processing'
);

-- Should classify a refund-pending purchase without refund rows as awaiting checkout
select is(
    event_purchase_refund_progress(
        jsonb_populate_record(null::event_purchase, '{"status": "refund-pending"}'::jsonb),
        false,
        null::event_purchase_refund,
        null::payment_job
    ),
    'awaiting-checkout',
    'Should classify a refund-pending purchase without refund rows as awaiting checkout'
);

-- Should classify a refunded purchase as refunded
select is(
    event_purchase_refund_progress(
        jsonb_populate_record(null::event_purchase, '{"status": "refunded"}'::jsonb),
        false,
        null::event_purchase_refund,
        null::payment_job
    ),
    'refunded',
    'Should classify a refunded purchase as refunded'
);

-- Should classify a terminal refund failure as recovery required
select is(
    event_purchase_refund_progress(
        jsonb_populate_record(null::event_purchase, '{"status": "refund-pending"}'::jsonb),
        false,
        jsonb_populate_record(null::event_purchase_refund, '{"status": "provider-failed", "terminal_failure": true}'::jsonb),
        jsonb_populate_record(null::payment_job, '{"attempt_count": 1, "status": "failed"}'::jsonb)
    ),
    'recovery-required',
    'Should classify a terminal refund failure as recovery required'
);

-- Should classify a terminal refund failure with an exhausted job as recovery required
select is(
    event_purchase_refund_progress(
        jsonb_populate_record(null::event_purchase, '{"status": "refund-pending"}'::jsonb),
        false,
        jsonb_populate_record(null::event_purchase_refund, '{"status": "provider-failed", "terminal_failure": true}'::jsonb),
        jsonb_populate_record(null::payment_job, '{"attempt_count": 10, "status": "failed"}'::jsonb)
    ),
    'recovery-required',
    'Should classify a terminal refund failure with an exhausted job as recovery required'
);

-- Should classify an exhausted job as a retryable failure
select is(
    event_purchase_refund_progress(
        jsonb_populate_record(null::event_purchase, '{"status": "refund-pending"}'::jsonb),
        false,
        jsonb_populate_record(null::event_purchase_refund, '{"status": "provider-failed", "terminal_failure": false}'::jsonb),
        jsonb_populate_record(null::payment_job, '{"attempt_count": 10, "status": "failed"}'::jsonb)
    ),
    'retryable-failure',
    'Should classify an exhausted job as a retryable failure'
);

-- Should return null for a canceled event's expired checkout hold without a session
select is(
    event_purchase_refund_progress(
        jsonb_populate_record(null::event_purchase, jsonb_build_object(
            'hold_expires_at', current_timestamp - interval '10 minutes',
            'status', 'pending'
        )),
        true,
        null::event_purchase_refund,
        null::payment_job
    ),
    null::text,
    'Should return null for a canceled event''s expired checkout hold without a session'
);

-- Should return null for a purchase outside any refund workflow
select is(
    event_purchase_refund_progress(
        jsonb_populate_record(null::event_purchase, '{"status": "completed"}'::jsonb),
        false,
        null::event_purchase_refund,
        null::payment_job
    ),
    null::text,
    'Should return null for a purchase outside any refund workflow'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
