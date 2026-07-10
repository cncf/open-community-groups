-- Add explicit recovery state and remove the obsolete refund success overload.

-- Extend the purchase lifecycle with a post-finalization recovery state
alter table event_purchase
    drop constraint event_purchase_status_check,
    add constraint event_purchase_status_check check (
        status = any(array[
            'completed',
            'expired',
            'pending',
            'refund-pending',
            'refund-recovery-pending',
            'refund-requested',
            'refunded'
        ]::text[])
    );

-- Preserve local finalization while a terminal provider failure awaits recovery
alter table event_purchase_refund
    add column recovery_completed_at timestamptz,
    add column recovery_completed_by_user_id uuid references "user",
    add column recovery_note text check (btrim(recovery_note) <> ''),
    add column recovery_reference text check (btrim(recovery_reference) <> ''),
    drop constraint event_purchase_refund_finalized_at_status_chk,
    add constraint event_purchase_refund_finalized_at_status_chk check (
        (status = 'finalized' and finalized_at is not null)
        or (status = 'provider-failed')
        or (
            status in ('provider-pending', 'provider-succeeded')
            and finalized_at is null
        )
    ),
    add constraint event_purchase_refund_recovery_completed_chk check (
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
            and status = 'provider-failed'
            and finalized_at is not null
        )
    );

-- Remove the unguarded legacy overload before reloading payment functions
drop function if exists record_event_purchase_refund_succeeded(uuid, text);
