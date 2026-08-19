-- Records an idempotent provider credit note and its current URLs.
create or replace function record_event_purchase_credit_note_succeeded(
    p_credit_note_id uuid,
    p_claim_id uuid,
    p_provider_credit_note_id text,
    p_provider_hosted_url text,
    p_provider_pdf_url text
)
returns void as $$
declare
    v_credit_note event_purchase_credit_note;
begin
    -- Validate the provider credit-note reference
    if nullif(btrim(p_provider_credit_note_id), '') is null then
        raise exception 'provider credit-note id is required';
    end if;

    -- Lock and load the claimed credit note
    select epcn.*
    into v_credit_note
    from event_purchase_credit_note epcn
    where epcn.event_purchase_credit_note_id = p_credit_note_id
    for update;

    -- Reject unknown credit-note work
    if not found then
        raise exception 'credit note not found';
    end if;

    -- Accept idempotent replay of the same issued credit note
    if v_credit_note.status = 'issued' then
        -- Reject replay for a different provider credit note
        if v_credit_note.provider_credit_note_id <> p_provider_credit_note_id then
            raise exception 'credit note has a different provider id';
        end if;
        return;
    end if;

    -- Validate claim ownership before issuing the credit note
    if v_credit_note.claim_id <> p_claim_id or v_credit_note.status <> 'processing' then
        raise exception 'credit-note claim is stale';
    end if;

    -- Persist the issued provider credit note
    update event_purchase_credit_note
    set
        claim_id = null,
        claimed_at = null,
        completed_at = current_timestamp,
        failure_message = null,
        provider_credit_note_id = p_provider_credit_note_id,
        provider_hosted_url = nullif(btrim(p_provider_hosted_url), ''),
        provider_pdf_url = nullif(btrim(p_provider_pdf_url), ''),
        status = 'issued',
        updated_at = current_timestamp
    where event_purchase_credit_note_id = p_credit_note_id;
end;
$$ language plpgsql;
