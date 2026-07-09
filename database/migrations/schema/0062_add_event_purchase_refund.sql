-- Add durable provider refund records for event purchases.

create table event_purchase_refund (
    event_purchase_refund_id uuid primary key default gen_random_uuid(),
    amount_minor bigint not null check (amount_minor > 0),
    created_at timestamptz default current_timestamp not null,
    currency_code text not null check (btrim(currency_code) <> ''),
    event_purchase_id uuid not null unique references event_purchase,
    idempotency_key text not null unique check (btrim(idempotency_key) <> ''),
    kind text not null check (
        kind = any(array['automatic-unfulfillable-checkout', 'refund-request-approval']::text[])
    ),
    payment_provider_id text not null references payment_provider,
    status text not null check (
        status = any(array[
            'finalized',
            'provider-failed',
            'provider-pending',
            'provider-succeeded'
        ]::text[])
    ),
    updated_at timestamptz default current_timestamp not null,

    event_refund_request_id uuid references event_refund_request,
    failure_message text check (btrim(failure_message) <> ''),
    finalized_at timestamptz,
    provider_refund_id text check (btrim(provider_refund_id) <> ''),
    provider_refunded_at timestamptz,

    constraint event_purchase_refund_finalized_at_status_chk check (
        (status = 'finalized' and finalized_at is not null)
        or (status <> 'finalized' and finalized_at is null)
    ),
    constraint event_purchase_refund_kind_request_chk check (
        (kind = 'automatic-unfulfillable-checkout' and event_refund_request_id is null)
        or (kind = 'refund-request-approval' and event_refund_request_id is not null)
    ),
    constraint event_purchase_refund_provider_refund_required_chk check (
        status not in ('finalized', 'provider-succeeded')
        or provider_refund_id is not null
    )
);

create index event_purchase_refund_event_refund_request_id_idx
    on event_purchase_refund (event_refund_request_id)
    where event_refund_request_id is not null;
create unique index event_purchase_refund_payment_provider_refund_id_idx
    on event_purchase_refund (payment_provider_id, provider_refund_id)
    where provider_refund_id is not null;
create index event_purchase_refund_status_idx on event_purchase_refund (status);
