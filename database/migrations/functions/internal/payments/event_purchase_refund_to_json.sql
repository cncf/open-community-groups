-- Projects a durable refund row and its payment job into the payload the refund worker consumes.
create or replace function event_purchase_refund_to_json(
    p_refund event_purchase_refund,
    p_job payment_job
)
returns jsonb as $$
    select jsonb_strip_nulls(jsonb_build_object(
        'amount_minor', p_refund.amount_minor,
        'attempt_count', p_job.attempt_count,
        'currency_code', p_refund.currency_code,
        'event_purchase_id', p_refund.event_purchase_id,
        'event_purchase_refund_id', p_refund.event_purchase_refund_id,
        'idempotency_key', p_job.idempotency_key,
        'kind', p_refund.kind,
        'payment_job_id', p_refund.payment_job_id,
        'payment_provider', p_refund.payment_provider_id,
        'status', p_refund.status,
        'terminal_failure', p_refund.terminal_failure,

        'claim_id', p_job.claim_id,
        'failure_message', p_job.failure_message,
        'finalized_at', epoch_seconds(p_refund.finalized_at),
        'provider_refund_id', p_refund.provider_refund_id,
        'provider_refunded_at', epoch_seconds(p_refund.provider_refunded_at)
    ));
$$ language sql immutable;
