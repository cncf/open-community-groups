-- Projects the lifecycle state of a payment job into the payload workers consume.
create or replace function payment_job_to_json(p_job payment_job)
returns jsonb as $$
    select jsonb_strip_nulls(jsonb_build_object(
        'attempt_count', p_job.attempt_count,
        'event_purchase_id', p_job.event_purchase_id,
        'idempotency_key', p_job.idempotency_key,
        'kind', p_job.kind,
        'payment_job_id', p_job.payment_job_id,
        'payment_provider', p_job.payment_provider_id,
        'status', p_job.status,

        'claim_id', p_job.claim_id,
        'failure_message', p_job.failure_message
    ));
$$ language sql immutable;
