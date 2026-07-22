-- Add durable notification delivery retry scheduling.

alter table notification
    add column if not exists next_delivery_attempt_at timestamptz,
    drop constraint if exists notification_next_delivery_attempt_at_chk,
    add constraint notification_next_delivery_attempt_at_chk check (
        next_delivery_attempt_at is null
        or delivery_status = 'pending'
    );

drop index if exists notification_not_processed_idx;

create index if not exists notification_not_processed_idx on notification (
    created_at,
    next_delivery_attempt_at,
    notification_id
)
where delivery_status = 'pending';
