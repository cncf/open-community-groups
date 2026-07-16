-- Add attendance cancellation state and durable refund worker processing.

-- Drop refund functions removed or replaced by the worker-backed workflow
drop function if exists approve_event_refund_request(uuid, uuid, uuid, uuid, text, text);
drop function if exists begin_event_refund_approval(uuid, uuid, uuid);
drop function if exists complete_event_purchase_refund_recovery(uuid, uuid, text, text);
drop function if exists complete_event_purchase_refund_recovery(uuid, uuid, text, text, text);
drop function if exists ensure_event_purchase_refund_started(uuid, text, text);
drop function if exists finalize_event_purchase_refund(uuid, uuid);
drop function if exists finalize_event_purchase_refund(uuid, uuid, jsonb);
drop function if exists record_automatic_refund_for_event_purchase(uuid, text);
drop function if exists record_event_purchase_refund_failed(uuid, text);
drop function if exists record_event_purchase_refund_pending(uuid, text, text);
drop function if exists record_event_purchase_refund_succeeded(uuid, text, text);
drop function if exists record_event_purchase_refund_terminal_failed(uuid, text, text, text);
drop function if exists reject_event_refund_request(uuid, uuid, uuid, uuid, text);
drop function if exists revert_event_refund_approval(uuid, uuid, uuid);

-- Record canceled attendance while preserving its prior attendee row
alter table event_attendee
    add column attendance_canceled_at timestamptz,
    add column attendance_canceled_by_user_id uuid references "user",
    drop constraint event_attendee_status_chk,
    add constraint event_attendee_attendance_canceled_chk check (
        (
            status = 'attendance-canceled'
            and attendance_canceled_at is not null
        )
        or (
            status <> 'attendance-canceled'
            and attendance_canceled_at is null
            and attendance_canceled_by_user_id is null
        )
    ),
    add constraint event_attendee_status_chk check (
        status in (
            'attendance-canceled',
            'confirmed',
            'invitation-canceled',
            'invitation-pending',
            'invitation-rejected',
            'registration-questions-pending'
        )
    );

-- Add worker scheduling, claim ownership, and cancellation refund context
alter table event_purchase_refund
    add column attempt_count int default 0 not null check (attempt_count >= 0),
    add column next_attempt_at timestamptz default current_timestamp not null,
    add column terminal_failure boolean default false not null,

    add column claim_id uuid,
    add column claimed_at timestamptz,
    add column initiated_by_user_id uuid references "user",
    add column review_note text,

    drop constraint event_purchase_refund_finalized_at_status_chk,
    drop constraint event_purchase_refund_kind_check,
    drop constraint event_purchase_refund_kind_request_chk,
    drop constraint event_purchase_refund_status_check,

    add constraint event_purchase_refund_claim_chk check (
        (
            status = 'processing'
            and claim_id is not null
            and claimed_at is not null
        )
        or (
            status <> 'processing'
            and claim_id is null
            and claimed_at is null
        )
    ),
    add constraint event_purchase_refund_finalized_at_status_chk check (
        (status = 'finalized' and finalized_at is not null)
        or (status = 'provider-failed')
        or (
            status in ('processing', 'provider-pending', 'provider-succeeded')
            and finalized_at is null
        )
    ),
    add constraint event_purchase_refund_kind_check check (
        kind = any(array[
            'automatic-unfulfillable-checkout',
            'event-cancellation',
            'refund-request-approval'
        ]::text[])
    ),
    add constraint event_purchase_refund_kind_request_chk check (
        (kind = 'automatic-unfulfillable-checkout' and event_refund_request_id is null)
        or (kind = 'event-cancellation')
        or (kind = 'refund-request-approval' and event_refund_request_id is not null)
    ),
    add constraint event_purchase_refund_status_check check (
        status = any(array[
            'finalized',
            'processing',
            'provider-failed',
            'provider-pending',
            'provider-succeeded'
        ]::text[])
    ),
    add constraint event_purchase_refund_terminal_failure_chk check (
        not terminal_failure
        or (
            status = 'provider-failed'
            and provider_refund_id is not null
        )
    );

-- Replace the status-only lookup with the worker claim queue access path
drop index event_purchase_refund_status_idx;
create index event_purchase_refund_status_idx
    on event_purchase_refund (payment_provider_id, status, next_attempt_at);
