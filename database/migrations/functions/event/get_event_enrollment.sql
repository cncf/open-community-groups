-- Returns the user's current enrollment state for an attendee-visible event.
create or replace function get_event_enrollment(
    p_community_id uuid,
    p_event_id uuid,
    p_user_id uuid
)
returns json as $$
    with
    -- Scope every downstream state lookup to an attendee-visible event.
    scoped_event as (
        select e.attendee_approval_required
        from event e
        join "group" g using (group_id)
        where e.event_id = p_event_id
        and g.community_id = p_community_id
        and g.active = true
        and e.deleted = false
        and e.published = true
        and (e.canceled = true or e.ends_at is null or e.ends_at >= current_timestamp)
    ),
    -- Resolve the shared enrollment facts only for a visible event.
    enrollment as (
        select en.*
        from scoped_event se
        cross join lateral event_user_enrollment(p_event_id, p_user_id) en
    ),
    -- Load the purchase the enrollment points at, with the event payment details.
    purchase_state as (
        select
            ep.amount_minor,
            ep.charge_model,
            ep.currency_code,
            ep.event_purchase_id,
            e.external_payment_instructions,
            e.external_payment_url,
            ep.hold_expires_at,
            ep.provider_checkout_url,
            ep.status
        from enrollment en
        join event_purchase ep on ep.event_purchase_id = en.event_purchase_id
        join event e using (event_id)
    ),
    -- Map the shared facts to the attendee-facing labels.
    enrollment_state as (
        select
            coalesce((select attendee_checked_in from enrollment), false) as is_checked_in,
            coalesce((
                select attendee_manually_invited
                    or admission_offer_source = 'organizer_invitation'
                from enrollment
            ), false) as manually_invited,
            coalesce((
                select case
                    when en.attendee_status = 'confirmed' then 'attendee'
                    when en.purchase_status = 'pending' then 'pending-payment'
                    when en.admission_offer_id is not null then 'invitation-approved'
                    when en.invitation_request_status = 'pending'
                        and se.attendee_approval_required then 'pending-approval'
                    when en.invitation_request_status = 'rejected'
                        and se.attendee_approval_required then 'rejected'
                    when en.waitlisted then 'waitlisted'
                    when en.latest_offer_expired then 'offer-expired'
                    else 'none'
                end
                from enrollment en
                cross join scoped_event se
            ), 'none') as status
    ),
    -- Attach the latest active review state for the selected purchase.
    refund_request_state as (
        select
            case
                when err.status = 'rejected' then nullif(btrim(err.review_note), '')
            end as rejection_reason,
            err.status
        from event_refund_request err
        join purchase_state ps using (event_purchase_id)
        where err.status in ('approved', 'approving', 'pending', 'rejected')
        order by err.created_at desc, err.event_refund_request_id desc
        limit 1
    )
    -- Project the normalized state into the Rust enrollment JSON contract.
    select (
        jsonb_build_object(
            'is_checked_in', es.is_checked_in,
            'purchase_amount_minor', (select amount_minor from purchase_state),
            'purchase_charge_model', (select charge_model from purchase_state),
            'refund_request_status', (select status from refund_request_state),
            'resume_checkout_url', (
                select provider_checkout_url
                from purchase_state
                where charge_model is distinct from 'external'
            ),
            'status', es.status
        )
        || jsonb_strip_nulls(jsonb_build_object(
            'admission_offer_id', (select admission_offer_id from enrollment),
            'event_ticket_type_id', (select admission_offer_event_ticket_type_id from enrollment),
            'external_payment', (
                select jsonb_strip_nulls(jsonb_build_object(
                    'amount_minor', amount_minor,
                    'currency_code', currency_code,
                    'deadline', epoch_seconds(hold_expires_at),
                    'instructions', external_payment_instructions,
                    'reference', event_purchase_id,
                    'url', external_payment_url
                ))
                from purchase_state
                where status = 'pending'
                and charge_model = 'external'
            ),
            'refund_rejection_reason', (select rejection_reason from refund_request_state)
        ))
        || case
            when es.manually_invited then jsonb_build_object('manually_invited', true)
            else '{}'::jsonb
        end
    )::json
    from enrollment_state es;
$$ language sql;
