-- Add durable delivery claim state for notification workers.

alter table notification
    add column delivery_attempts integer not null default 0
        constraint notification_delivery_attempts_chk check (delivery_attempts >= 0),
    add column delivery_claimed_at timestamptz,
    add column delivery_status text not null default 'pending'
        constraint notification_delivery_status_chk check (
            delivery_status in (
                'delivery-unknown',
                'failed',
                'pending',
                'processed',
                'processing'
            )
        );

update notification
set delivery_status = case
    when processed = true and error is null then 'processed'
    when processed = true then 'failed'
    else 'pending'
end;

drop index notification_not_processed_idx;

alter table notification
    drop column processed;

create index notification_not_processed_idx on notification (created_at, notification_id)
where delivery_status = 'pending';
