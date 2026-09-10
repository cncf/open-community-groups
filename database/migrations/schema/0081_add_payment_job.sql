-- Moves the worker lifecycle of refunds, credit notes and application-fee adjustments into one payment_job table.

-- Remove the per-family lifecycle functions and the projection whose signature changes
drop function if exists claim_event_purchase_application_fee_adjustment(text);
drop function if exists claim_event_purchase_credit_note(text);
drop function if exists claim_event_purchase_refund(text);
drop function if exists complete_event_purchase_application_fee_adjustment_recovery(uuid, uuid, uuid, text, text, text);
drop function if exists complete_event_purchase_credit_note_recovery(uuid, uuid, uuid, text, text, text);
drop function if exists event_purchase_refund_to_json(event_purchase_refund);
drop function if exists record_event_purchase_application_fee_adjustment_failure(uuid, uuid, text);
drop function if exists record_event_purchase_credit_note_failure(uuid, uuid, text);
drop function if exists record_event_purchase_refund_retryable_failure(uuid, uuid, text);
drop function if exists requeue_event_purchase_application_fee_adjustment(uuid, uuid);
drop function if exists requeue_event_purchase_credit_note(uuid, uuid);
drop function if exists requeue_event_purchase_refund(uuid, uuid);
drop function if exists requeue_stale_event_purchase_application_fee_adjustment_claims();
drop function if exists requeue_stale_event_purchase_credit_note_claims();
drop function if exists requeue_stale_event_purchase_refund_claims();

-- Shared lifecycle of every durable payment job; domain tables keep their typed outcome
create table payment_job (
    payment_job_id uuid primary key default gen_random_uuid(),
    attempt_count int default 0 not null check (attempt_count >= 0),
    created_at timestamptz default current_timestamp not null,
    event_purchase_id uuid not null references event_purchase,
    idempotency_key text not null unique check (btrim(idempotency_key) <> ''),
    kind text not null,
    next_attempt_at timestamptz default current_timestamp not null,
    payment_provider_id text not null references payment_provider,
    status text default 'pending' not null,
    updated_at timestamptz default current_timestamp not null,

    claim_id uuid,
    claimed_at timestamptz,
    completed_at timestamptz,
    failure_message text check (btrim(failure_message) <> ''),
    recovery_completed_at timestamptz,
    recovery_completed_by_user_id uuid references "user",
    recovery_note text check (btrim(recovery_note) <> ''),
    recovery_reference text check (btrim(recovery_reference) <> ''),

    constraint payment_job_claim_chk check (
        (status = 'processing' and claim_id is not null and claimed_at is not null)
        or (status <> 'processing' and claim_id is null and claimed_at is null)
    ),
    constraint payment_job_completed_chk check (
        (status = 'completed' and completed_at is not null)
        or (status <> 'completed' and completed_at is null)
    ),
    constraint payment_job_kind_chk check (
        kind = any(array[
            'event-purchase-application-fee-adjustment',
            'event-purchase-credit-note',
            'event-purchase-refund'
        ]::text[])
    ),
    constraint payment_job_recovery_chk check (
        (
            recovery_completed_at is null
            and recovery_completed_by_user_id is null
            and recovery_note is null
            and recovery_reference is null
        )
        or (
            recovery_completed_at is not null
            and recovery_completed_by_user_id is not null
            and recovery_note is not null
            and recovery_reference is not null
            and status = 'completed'
        )
    ),
    constraint payment_job_status_chk check (
        status = any(array['completed', 'failed', 'pending', 'processing']::text[])
    )
);

create index payment_job_claimed_at_idx
    on payment_job (claimed_at)
    where claimed_at is not null;
create index payment_job_event_purchase_id_idx on payment_job (event_purchase_id);
create index payment_job_work_idx on payment_job (kind, status, next_attempt_at);

-- Link every refund to a lifecycle row before moving its worker state
alter table event_purchase_refund
    add column payment_job_id uuid;

update event_purchase_refund
set payment_job_id = gen_random_uuid();

insert into payment_job (
    payment_job_id,
    attempt_count,
    created_at,
    event_purchase_id,
    idempotency_key,
    kind,
    next_attempt_at,
    payment_provider_id,
    status,
    updated_at,

    claim_id,
    claimed_at,
    completed_at,
    failure_message,
    recovery_completed_at,
    recovery_completed_by_user_id,
    recovery_note,
    recovery_reference
)
select
    epr.payment_job_id,
    case
        -- Provider-confirmed refunds awaiting finalization were claimable without a cap
        when epr.provider_refunded_at is not null and epr.finalized_at is null then 0
        else epr.attempt_count
    end,
    epr.created_at,
    epr.event_purchase_id,
    epr.idempotency_key,
    'event-purchase-refund',
    case
        -- Finalization work becomes due immediately under the shared attempt cap
        when epr.provider_refunded_at is not null and epr.finalized_at is null then current_timestamp
        else epr.next_attempt_at
    end,
    epr.payment_provider_id,
    case
        when epr.status = 'finalized' or epr.recovery_completed_at is not null then 'completed'
        when epr.status = 'processing' then 'processing'
        when epr.status = 'provider-failed' then 'failed'
        else 'pending'
    end,
    epr.updated_at,

    epr.claim_id,
    epr.claimed_at,
    case
        when epr.status = 'finalized' then epr.finalized_at
        else epr.recovery_completed_at
    end,
    case
        when epr.status = 'finalized' or epr.recovery_completed_at is not null then null
        when epr.provider_refunded_at is not null and epr.finalized_at is null then null
        else epr.failure_message
    end,
    epr.recovery_completed_at,
    epr.recovery_completed_by_user_id,
    epr.recovery_note,
    epr.recovery_reference
from event_purchase_refund epr;

-- Retryable worker failures now live on the job; the refund keeps only provider state
alter table event_purchase_refund
    drop constraint event_purchase_refund_claim_chk,
    drop constraint event_purchase_refund_finalized_at_status_chk,
    drop constraint event_purchase_refund_recovery_completed_chk,
    drop constraint event_purchase_refund_status_check;

-- Locally finalized rows stay provider-failed, the only status that allows finalized_at
update event_purchase_refund
set status = case
    when provider_refunded_at is not null then 'provider-succeeded'
    else 'provider-pending'
end
where status = 'processing'
or (
    status = 'provider-failed'
    and not terminal_failure
    and finalized_at is null
);

drop index event_purchase_refund_status_idx;

alter table event_purchase_refund
    drop column attempt_count,
    drop column claim_id,
    drop column claimed_at,
    drop column failure_message,
    drop column idempotency_key,
    drop column next_attempt_at,
    drop column recovery_completed_at,
    drop column recovery_completed_by_user_id,
    drop column recovery_note,
    drop column recovery_reference,
    alter column payment_job_id set not null,
    add constraint event_purchase_refund_payment_job_id_fkey
        foreign key (payment_job_id) references payment_job,
    add constraint event_purchase_refund_payment_job_id_key unique (payment_job_id),
    add constraint event_purchase_refund_finalized_at_status_chk check (
        (status = 'finalized' and finalized_at is not null)
        or (status = 'provider-failed')
        or (
            status in ('provider-pending', 'provider-succeeded')
            and finalized_at is null
        )
    ),
    add constraint event_purchase_refund_status_check check (
        status = any(array[
            'finalized',
            'provider-failed',
            'provider-pending',
            'provider-succeeded'
        ]::text[])
    );

-- Link every credit note to a lifecycle row before dropping its worker columns
alter table event_purchase_credit_note
    add column payment_job_id uuid;

update event_purchase_credit_note
set payment_job_id = gen_random_uuid();

insert into payment_job (
    payment_job_id,
    attempt_count,
    created_at,
    event_purchase_id,
    idempotency_key,
    kind,
    next_attempt_at,
    payment_provider_id,
    status,
    updated_at,

    claim_id,
    claimed_at,
    completed_at,
    failure_message,
    recovery_completed_at,
    recovery_completed_by_user_id,
    recovery_note,
    recovery_reference
)
select
    epcn.payment_job_id,
    epcn.attempt_count,
    epcn.created_at,
    epr.event_purchase_id,
    epcn.idempotency_key,
    'event-purchase-credit-note',
    epcn.next_attempt_at,
    epcn.payment_provider_id,
    case
        when epcn.status = 'issued' then 'completed'
        else epcn.status
    end,
    epcn.updated_at,

    epcn.claim_id,
    epcn.claimed_at,
    epcn.completed_at,
    epcn.failure_message,
    epcn.recovery_completed_at,
    epcn.recovery_completed_by_user_id,
    epcn.recovery_note,
    epcn.recovery_reference
from event_purchase_credit_note epcn
join event_purchase_refund epr on epr.event_purchase_refund_id = epcn.event_purchase_refund_id;

drop index event_purchase_credit_note_work_idx;

alter table event_purchase_credit_note
    drop constraint event_purchase_credit_note_claim_chk,
    drop constraint event_purchase_credit_note_recovery_chk,
    drop constraint event_purchase_credit_note_status_chk,
    drop constraint event_purchase_credit_note_terminal_chk,
    drop column attempt_count,
    drop column claim_id,
    drop column claimed_at,
    drop column completed_at,
    drop column failure_message,
    drop column idempotency_key,
    drop column next_attempt_at,
    drop column recovery_completed_at,
    drop column recovery_completed_by_user_id,
    drop column recovery_note,
    drop column recovery_reference,
    drop column status,
    alter column payment_job_id set not null,
    add constraint event_purchase_credit_note_payment_job_id_fkey
        foreign key (payment_job_id) references payment_job,
    add constraint event_purchase_credit_note_payment_job_id_key unique (payment_job_id);

-- Link every application-fee adjustment to a lifecycle row before dropping its worker columns
alter table event_purchase_application_fee_adjustment
    add column payment_job_id uuid;

update event_purchase_application_fee_adjustment
set payment_job_id = gen_random_uuid();

insert into payment_job (
    payment_job_id,
    attempt_count,
    created_at,
    event_purchase_id,
    idempotency_key,
    kind,
    next_attempt_at,
    payment_provider_id,
    status,
    updated_at,

    claim_id,
    claimed_at,
    completed_at,
    failure_message,
    recovery_completed_at,
    recovery_completed_by_user_id,
    recovery_note,
    recovery_reference
)
select
    epafa.payment_job_id,
    epafa.attempt_count,
    epafa.created_at,
    epafa.event_purchase_id,
    epafa.idempotency_key,
    'event-purchase-application-fee-adjustment',
    epafa.next_attempt_at,
    ep.payment_provider_id,
    epafa.status,
    epafa.updated_at,

    epafa.claim_id,
    epafa.claimed_at,
    epafa.completed_at,
    epafa.failure_message,
    epafa.recovery_completed_at,
    epafa.recovery_completed_by_user_id,
    epafa.recovery_note,
    epafa.recovery_reference
from event_purchase_application_fee_adjustment epafa
join event_purchase ep on ep.event_purchase_id = epafa.event_purchase_id;

drop index event_purchase_application_fee_adjustment_idempotency_key_idx;
drop index event_purchase_application_fee_adjustment_work_idx;

alter table event_purchase_application_fee_adjustment
    drop constraint event_purchase_application_fee_adjustment_claim_chk,
    drop constraint event_purchase_application_fee_adjustment_recovery_chk,
    drop constraint event_purchase_application_fee_adjustment_status_chk,
    drop constraint event_purchase_application_fee_adjustment_terminal_chk,
    drop column attempt_count,
    drop column claim_id,
    drop column claimed_at,
    drop column completed_at,
    drop column failure_message,
    drop column idempotency_key,
    drop column next_attempt_at,
    drop column recovery_completed_at,
    drop column recovery_completed_by_user_id,
    drop column recovery_note,
    drop column recovery_reference,
    drop column status,
    alter column payment_job_id set not null,
    add constraint event_purchase_application_fee_adjustment_payment_job_id_fkey
        foreign key (payment_job_id) references payment_job,
    add constraint event_purchase_application_fee_adjustment_payment_job_id_key
        unique (payment_job_id);

-- Rejects completing a payment job whose domain row lacks its provider outcome.
create or replace function check_payment_job_completion_outcome()
returns trigger as $$
declare
    v_has_outcome boolean;
begin
    -- Resolve the typed outcome the completed job must have written
    case new.kind
        -- Fee adjustments complete with the provider application-fee refund
        when 'event-purchase-application-fee-adjustment' then
            select epafa.provider_application_fee_refund_id is not null
            into v_has_outcome
            from event_purchase_application_fee_adjustment epafa
            where epafa.payment_job_id = new.payment_job_id;

        -- Credit notes complete with the provider credit-note document
        when 'event-purchase-credit-note' then
            select epcn.provider_credit_note_id is not null
            into v_has_outcome
            from event_purchase_credit_note epcn
            where epcn.payment_job_id = new.payment_job_id;

        -- Refunds complete once their local finalization is recorded
        when 'event-purchase-refund' then
            select epr.finalized_at is not null
            into v_has_outcome
            from event_purchase_refund epr
            where epr.payment_job_id = new.payment_job_id;

        -- Reject kinds without a completion contract
        else
            raise exception 'payment job kind has no completion outcome';
    end case;

    -- Reject completion without a domain row or without its outcome
    if not coalesce(v_has_outcome, false) then
        raise exception 'payment job completed without its provider outcome';
    end if;

    return new;
end;
$$ language plpgsql;

create trigger payment_job_completion_outcome_check
before update on payment_job
for each row
when (new.status = 'completed')
execute function check_payment_job_completion_outcome();

-- Check completed jobs inserted directly once their domain row exists in the same transaction
create constraint trigger payment_job_completion_outcome_insert_check
after insert on payment_job
deferrable initially deferred
for each row
when (new.status = 'completed')
execute function check_payment_job_completion_outcome();

-- Rejects a domain row without its provider outcome while its payment job is completed.
create or replace function check_payment_job_domain_outcome()
returns trigger as $$
declare
    v_has_outcome boolean;
    v_job_status text;
begin
    -- Load the lifecycle state of the job the row belongs to
    select pj.status
    into v_job_status
    from payment_job pj
    where pj.payment_job_id = new.payment_job_id;

    -- Only completed jobs require their outcome
    if v_job_status is distinct from 'completed' then
        return new;
    end if;

    -- Resolve the typed outcome column of the table
    case tg_table_name
        -- Fee adjustments complete with the provider application-fee refund
        when 'event_purchase_application_fee_adjustment' then
            v_has_outcome := new.provider_application_fee_refund_id is not null;

        -- Credit notes complete with the provider credit-note document
        when 'event_purchase_credit_note' then
            v_has_outcome := new.provider_credit_note_id is not null;

        -- Refunds complete once their local finalization is recorded
        when 'event_purchase_refund' then
            v_has_outcome := new.finalized_at is not null;

        -- Reject tables without a completion contract
        else
            raise exception 'payment job domain table has no completion outcome';
    end case;

    -- Reject clearing or omitting the outcome of completed work
    if not v_has_outcome then
        raise exception 'payment job completed without its provider outcome';
    end if;

    return new;
end;
$$ language plpgsql;

create trigger event_purchase_application_fee_adjustment_job_outcome_check
before insert or update on event_purchase_application_fee_adjustment
for each row
execute function check_payment_job_domain_outcome();

create trigger event_purchase_credit_note_job_outcome_check
before insert or update on event_purchase_credit_note
for each row
execute function check_payment_job_domain_outcome();

create trigger event_purchase_refund_job_outcome_check
before insert or update on event_purchase_refund
for each row
execute function check_payment_job_domain_outcome();
