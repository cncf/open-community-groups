-- Records an idempotent provider credit note and completes its payment job.
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
    v_job payment_job;
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

    -- Lock the lifecycle row that owns the claim
    select pj.*
    into v_job
    from payment_job pj
    where pj.payment_job_id = v_credit_note.payment_job_id
    for update;

    -- Accept idempotent replay of the same issued credit note
    if v_job.status = 'completed' then
        -- Reject replay for a different provider credit note
        if v_credit_note.provider_credit_note_id <> p_provider_credit_note_id then
            raise exception 'credit note has a different provider id';
        end if;

        return;
    end if;

    -- Validate claim ownership before issuing the credit note
    if v_job.claim_id <> p_claim_id or v_job.status <> 'processing' then
        raise exception 'credit-note claim is stale';
    end if;

    -- Persist the issued document and complete the job
    perform apply_event_purchase_credit_note_outcome(
        v_credit_note,
        p_provider_credit_note_id,
        p_provider_hosted_url,
        p_provider_pdf_url
    );
    perform complete_payment_job(v_job.payment_job_id, p_claim_id);
end;
$$ language plpgsql;
