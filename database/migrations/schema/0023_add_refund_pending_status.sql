-- Add an intermediate automatic refund state for webhook retries.

alter table event_purchase
    drop constraint if exists event_purchase_status_check;

alter table event_purchase
    add constraint event_purchase_status_check check (
        status = any(array[
            'completed',
            'expired',
            'pending',
            'refund-pending',
            'refund-requested',
            'refunded'
        ]::text[])
    );
