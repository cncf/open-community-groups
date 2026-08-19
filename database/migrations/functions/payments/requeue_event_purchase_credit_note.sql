-- Requeues an exhausted credit note.
create or replace function requeue_event_purchase_credit_note(
    p_group_id uuid,
    p_credit_note_id uuid
)
returns void as $$
begin
    -- Reset exhausted work for another bounded automatic attempt cycle
    update event_purchase_credit_note epcn
    set
        attempt_count = 0,
        failure_message = null,
        next_attempt_at = current_timestamp,
        status = 'pending',
        updated_at = current_timestamp
    from event_purchase_refund epr
    join event_purchase ep using (event_purchase_id)
    join event e using (event_id)
    where epcn.event_purchase_refund_id = epr.event_purchase_refund_id
    and e.group_id = p_group_id
    and epcn.event_purchase_credit_note_id = p_credit_note_id
    and epcn.status = 'failed'
    and epcn.attempt_count >= 10;

    -- Reject missing, cross-group, or ineligible work
    if not found then
        raise exception 'retryable credit note not found';
    end if;
end;
$$ language plpgsql;
