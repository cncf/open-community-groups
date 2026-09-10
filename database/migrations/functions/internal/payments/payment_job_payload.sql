-- Builds the kind-specific provider context a worker needs for a claimed payment job.
create or replace function payment_job_payload(p_job payment_job)
returns jsonb as $$
declare
    v_adjustment event_purchase_application_fee_adjustment;
    v_community_id uuid;
    v_credit_note event_purchase_credit_note;
    v_event_id uuid;
    v_purchase event_purchase;
    v_refund event_purchase_refund;
begin
    -- Load the purchase every payment job hangs off
    select ep.*
    into v_purchase
    from event_purchase ep
    where ep.event_purchase_id = p_job.event_purchase_id;

    -- Reject jobs whose purchase disappeared
    if not found then
        raise exception 'event purchase not found';
    end if;

    -- Build the payload of the job kind
    case p_job.kind
        -- Fee adjustments refund part of the platform fee of a direct charge
        when 'event-purchase-application-fee-adjustment' then
            select epafa.*
            into v_adjustment
            from event_purchase_application_fee_adjustment epafa
            where epafa.payment_job_id = p_job.payment_job_id;

            -- Reject jobs without their adjustment row
            if not found then
                raise exception 'application-fee adjustment not found';
            end if;

            -- Reject claims whose immutable provider context is incomplete
            if nullif(btrim(v_purchase.connected_seller_id), '') is null
               or nullif(btrim(v_purchase.currency_code), '') is null
               or nullif(btrim(v_purchase.provider_application_fee_id), '') is null then
                raise exception 'application-fee adjustment is missing provider context';
            end if;

            return jsonb_build_object(
                'application_fee_adjustment', jsonb_build_object(
                    'amount_minor', v_adjustment.amount_minor,
                    'connected_seller_id', v_purchase.connected_seller_id,
                    'currency_code', v_purchase.currency_code,
                    'event_purchase_application_fee_adjustment_id',
                        v_adjustment.event_purchase_application_fee_adjustment_id,
                    'kind', v_adjustment.kind,
                    'provider_application_fee_id', v_purchase.provider_application_fee_id
                )
            );

        -- Credit notes document a confirmed customer refund against its invoice
        when 'event-purchase-credit-note' then
            select epcn.*
            into v_credit_note
            from event_purchase_credit_note epcn
            where epcn.payment_job_id = p_job.payment_job_id;

            -- Reject jobs without their credit-note row
            if not found then
                raise exception 'credit note not found';
            end if;

            -- Load the confirmed refund the credit note documents
            select epr.*
            into v_refund
            from event_purchase_refund epr
            where epr.event_purchase_refund_id = v_credit_note.event_purchase_refund_id;

            -- Reject claims whose immutable provider context is incomplete
            if nullif(btrim(v_purchase.connected_seller_id), '') is null
               or nullif(btrim(v_purchase.provider_invoice_id), '') is null
               or nullif(btrim(v_refund.provider_refund_id), '') is null then
                raise exception 'credit note is missing provider context';
            end if;

            return jsonb_build_object(
                'credit_note', jsonb_build_object(
                    'amount_minor', v_credit_note.amount_minor,
                    'connected_seller_id', v_purchase.connected_seller_id,
                    'event_purchase_credit_note_id', v_credit_note.event_purchase_credit_note_id,
                    'event_purchase_refund_id', v_credit_note.event_purchase_refund_id,
                    'provider_invoice_id', v_purchase.provider_invoice_id,
                    'provider_refund_id', v_refund.provider_refund_id,
                    'tax_amount_minor', v_credit_note.tax_amount_minor
                )
            );

        -- Refunds return the provider payment and the notification context
        when 'event-purchase-refund' then
            select epr.*
            into v_refund
            from event_purchase_refund epr
            where epr.payment_job_id = p_job.payment_job_id;

            -- Reject jobs without their refund row
            if not found then
                raise exception 'event purchase refund not found';
            end if;

            -- Resolve the community and event the notification is composed for
            select g.community_id, e.event_id
            into v_community_id, v_event_id
            from event e
            join "group" g on g.group_id = e.group_id
            where e.event_id = v_purchase.event_id;

            -- Reject purchases without the connected account that received the charge
            if nullif(btrim(v_purchase.connected_seller_id), '') is null then
                raise exception 'event purchase is missing connected seller account';
            end if;

            return jsonb_build_object(
                'refund', event_purchase_refund_to_json(v_refund, p_job)
                    || jsonb_strip_nulls(jsonb_build_object(
                        'community_id', v_community_id,
                        'connected_seller_id', v_purchase.connected_seller_id,
                        'event_id', v_event_id,
                        'provider_payment_reference', v_purchase.provider_payment_reference
                    ))
            );

        -- Reject kinds without a worker payload
        else
            raise exception 'payment job kind has no worker payload';
    end case;
end;
$$ language plpgsql;
