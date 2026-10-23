-- Tests rejecting provider refund results for missing refunds or stale worker claims.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set claimID 'f24a0000-0000-0000-0000-000000000001'
\set jobID 'f24a0000-0000-0000-0000-000000000002'
\set otherClaimID 'f24a0000-0000-0000-0000-000000000003'
\set refundID 'f24a0000-0000-0000-0000-000000000004'

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept a result from the worker that claimed the job
select lives_ok(
    format(
        $$select ensure_event_purchase_refund_claim(
            jsonb_populate_record(null::event_purchase_refund, jsonb_build_object('event_purchase_refund_id', %L::uuid)),
            jsonb_populate_record(null::payment_job, jsonb_build_object('claim_id', %L::uuid, 'payment_job_id', %L::uuid)),
            %L::uuid
        )$$,
        :'refundID',
        :'claimID',
        :'jobID',
        :'claimID'
    ),
    'Should accept a result from the worker that claimed the job'
);

-- Should accept an unclaimed job when no claim is expected
select lives_ok(
    format(
        $$select ensure_event_purchase_refund_claim(
            jsonb_populate_record(null::event_purchase_refund, jsonb_build_object('event_purchase_refund_id', %L::uuid)),
            jsonb_populate_record(null::payment_job, jsonb_build_object('payment_job_id', %L::uuid)),
            null
        )$$,
        :'refundID',
        :'jobID'
    ),
    'Should accept an unclaimed job when no claim is expected'
);

-- Should check the refund row before the worker claim
select throws_ok(
    format(
        $$select ensure_event_purchase_refund_claim(
            null::event_purchase_refund,
            null::payment_job,
            %L::uuid
        )$$,
        :'claimID'
    ),
    'P0001',
    'event purchase refund not found',
    'Should check the refund row before the worker claim'
);

-- Should reject a claimed result when the job is no longer claimed
select throws_ok(
    format(
        $$select ensure_event_purchase_refund_claim(
            jsonb_populate_record(null::event_purchase_refund, jsonb_build_object('event_purchase_refund_id', %L::uuid)),
            jsonb_populate_record(null::payment_job, jsonb_build_object('payment_job_id', %L::uuid)),
            %L::uuid
        )$$,
        :'refundID',
        :'jobID',
        :'claimID'
    ),
    'P0001',
    'event purchase refund claim is stale',
    'Should reject a claimed result when the job is no longer claimed'
);

-- Should reject a missing refund row
select throws_ok(
    $$select ensure_event_purchase_refund_claim(null::event_purchase_refund, null::payment_job, null)$$,
    'P0001',
    'event purchase refund not found',
    'Should reject a missing refund row'
);

-- Should reject a result from another worker claim
select throws_ok(
    format(
        $$select ensure_event_purchase_refund_claim(
            jsonb_populate_record(null::event_purchase_refund, jsonb_build_object('event_purchase_refund_id', %L::uuid)),
            jsonb_populate_record(null::payment_job, jsonb_build_object('claim_id', %L::uuid, 'payment_job_id', %L::uuid)),
            %L::uuid
        )$$,
        :'refundID',
        :'otherClaimID',
        :'jobID',
        :'claimID'
    ),
    'P0001',
    'event purchase refund claim is stale',
    'Should reject a result from another worker claim'
);

-- Should reject an unclaimed result when a worker claims the job
select throws_ok(
    format(
        $$select ensure_event_purchase_refund_claim(
            jsonb_populate_record(null::event_purchase_refund, jsonb_build_object('event_purchase_refund_id', %L::uuid)),
            jsonb_populate_record(null::payment_job, jsonb_build_object('claim_id', %L::uuid, 'payment_job_id', %L::uuid)),
            null
        )$$,
        :'refundID',
        :'claimID',
        :'jobID'
    ),
    'P0001',
    'event purchase refund claim is stale',
    'Should reject an unclaimed result when a worker claims the job'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
