-- Used by the dashboard refund approval flow before calling the payments
-- provider: locks the refund request, moves it from pending to approving when
-- needed, and returns the purchase summary required for the refund step
create or replace function begin_event_refund_approval(
    p_group_id uuid,
    p_event_id uuid,
    p_user_id uuid
)
returns jsonb as $$
declare
    v_amount_minor bigint;
    v_completed_at timestamptz;
    v_currency_code text;
    v_discount_amount_minor bigint;
    v_discount_code text;
    v_event_purchase_id uuid;
    v_event_ticket_type_id uuid;
    v_hold_expires_at timestamptz;
    v_provider_checkout_url text;
    v_provider_payment_reference text;
    v_provider_session_id text;
    v_refund_request_status text;
    v_refunded_at timestamptz;
    v_status text;
    v_ticket_title text;
begin
    -- Lock the current refund request state before moving it forward
    select
        ep.amount_minor,
        ep.completed_at,
        ep.currency_code,
        ep.discount_amount_minor,
        ep.discount_code,
        ep.event_purchase_id,
        ep.event_ticket_type_id,
        ep.hold_expires_at,
        ep.provider_checkout_url,
        ep.provider_payment_reference,
        ep.provider_checkout_session_id,
        ep.refunded_at,
        err.status,
        ep.status,
        ep.ticket_title
    into
        v_amount_minor,
        v_completed_at,
        v_currency_code,
        v_discount_amount_minor,
        v_discount_code,
        v_event_purchase_id,
        v_event_ticket_type_id,
        v_hold_expires_at,
        v_provider_checkout_url,
        v_provider_payment_reference,
        v_provider_session_id,
        v_refunded_at,
        v_refund_request_status,
        v_status,
        v_ticket_title
    from event_purchase ep
    join event e on e.event_id = ep.event_id
    join "group" g on g.group_id = e.group_id
    join event_refund_request err on err.event_purchase_id = ep.event_purchase_id
    where g.group_id = p_group_id
    and ep.event_id = p_event_id
    and ep.user_id = p_user_id
    and ep.status = 'refund-requested'
    and err.status in ('approving', 'pending')
    for update of ep, err;

    if not found then
        raise exception 'refund request not found';
    end if;

    -- Move pending requests into the provider approval step
    if v_refund_request_status = 'pending' then
        update event_refund_request
        set
            status = 'approving',
            updated_at = current_timestamp
        where event_purchase_id = v_event_purchase_id
        and status = 'pending';
    end if;

    -- Return the purchase summary used by the provider refund step
    return jsonb_strip_nulls(
        jsonb_build_object(
            'amount_minor', v_amount_minor,
            'currency_code', v_currency_code,
            'discount_amount_minor', v_discount_amount_minor,
            'event_purchase_id', v_event_purchase_id,
            'event_ticket_type_id', v_event_ticket_type_id,
            'status', v_status,
            'ticket_title', v_ticket_title,

            'completed_at', extract(epoch from v_completed_at)::bigint,
            'discount_code', v_discount_code,
            'hold_expires_at', extract(epoch from v_hold_expires_at)::bigint,
            'provider_checkout_url', v_provider_checkout_url,
            'provider_payment_reference', v_provider_payment_reference,
            'provider_session_id', v_provider_session_id,
            'refunded_at', extract(epoch from v_refunded_at)::bigint
        )
    );
end;
$$ language plpgsql;
