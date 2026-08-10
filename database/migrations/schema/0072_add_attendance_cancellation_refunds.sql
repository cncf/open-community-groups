-- Adds organizer-initiated attendance cancellation refunds.

alter table event_purchase_refund
    drop constraint event_purchase_refund_kind_check,
    drop constraint event_purchase_refund_kind_request_chk,
    add constraint event_purchase_refund_kind_check check (
        kind = any(array[
            'attendance-cancellation',
            'automatic-unfulfillable-checkout',
            'event-cancellation',
            'refund-request-approval'
        ]::text[])
    ),
    add constraint event_purchase_refund_kind_request_chk check (
        (kind = 'attendance-cancellation' and event_refund_request_id is not null)
        or (kind = 'automatic-unfulfillable-checkout' and event_refund_request_id is null)
        or (kind = 'event-cancellation')
        or (kind = 'refund-request-approval' and event_refund_request_id is not null)
    );
