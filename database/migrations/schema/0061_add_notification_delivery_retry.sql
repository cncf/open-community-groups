-- Add durable notification delivery retry scheduling.

alter table notification
    add column next_delivery_attempt_at timestamptz,
    add constraint notification_next_delivery_attempt_at_chk check (
        next_delivery_attempt_at is null
        or delivery_status = 'pending'
    );

drop index notification_not_processed_idx;

create index notification_not_processed_idx on notification (
    created_at,
    next_delivery_attempt_at,
    notification_id
)
where delivery_status = 'pending';
