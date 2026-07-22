-- Apply safely to both the pre-baseline production schema and fresh baseline databases.
drop function if exists claim_pending_notification();

create index if not exists notification_delivery_claimed_at_idx
    on notification (delivery_claimed_at)
    where delivery_claimed_at is not null;
