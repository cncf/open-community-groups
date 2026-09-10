-- Creates the lifecycle row of a durable payment job, returning null when the idempotency key already exists.
create or replace function enqueue_payment_job(
    p_kind text,
    p_payment_provider_id text,
    p_event_purchase_id uuid,
    p_idempotency_key text
)
returns uuid as $$
    insert into payment_job (
        event_purchase_id,
        idempotency_key,
        kind,
        payment_provider_id
    ) values (
        p_event_purchase_id,
        p_idempotency_key,
        p_kind,
        p_payment_provider_id
    )
    on conflict (idempotency_key) do nothing
    returning payment_job_id;
$$ language sql;
