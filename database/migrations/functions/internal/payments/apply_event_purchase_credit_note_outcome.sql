-- Records the issued provider credit note and its current document URLs.
create or replace function apply_event_purchase_credit_note_outcome(
    p_credit_note event_purchase_credit_note,
    p_provider_credit_note_id text,
    p_provider_hosted_url text,
    p_provider_pdf_url text
)
returns void as $$
begin
    -- Persist the issued provider document
    update event_purchase_credit_note
    set
        provider_credit_note_id = p_provider_credit_note_id,
        provider_hosted_url = nullif(btrim(p_provider_hosted_url), ''),
        provider_pdf_url = nullif(btrim(p_provider_pdf_url), ''),
        updated_at = current_timestamp
    where event_purchase_credit_note_id = p_credit_note.event_purchase_credit_note_id;
end;
$$ language plpgsql;
