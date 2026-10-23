-- Returns the user's current enrollment state for an attendee-visible event.
-- The status label follows this precedence: attendee, pending-payment,
-- invitation-approved, pending-approval, rejected, waitlisted, offer-expired,
-- none. Events stop being attendee-visible once they are past, unless they
-- were canceled.
create or replace function get_event_enrollment(
    p_community_id uuid,
    p_event_id uuid,
    p_user_id uuid
)
returns json as $$
    with
    -- Scope every downstream state lookup to an attendee-visible event
    scoped_event as (
        select e.attendee_approval_required
        from event e
        join "group" g using (group_id)
        where e.event_id = p_event_id
        and g.community_id = p_community_id
        and g.active = true
        and e.deleted = false
        and e.published = true
        and (e.canceled or not event_is_past(e))
    ),
    -- Resolve the shared enrollment facts only for a visible event
    enrollment as (
        select en.*
        from scoped_event se
        cross join lateral event_user_enrollment(p_event_id, p_user_id) en
    ),
    -- Load the purchase the enrollment points at, with the event payment details
    purchase_state as (
        select
            e as event,
            ep as purchase
        from enrollment en
        join event_purchase ep on ep.event_purchase_id = en.event_purchase_id
        join event e using (event_id)
    ),
    -- Map the shared facts to the attendee-facing labels
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
                    -- Report a held seat first
                    when en.attendee_status = 'confirmed' then 'attendee'
                    -- Report a resumable checkout hold
                    when en.purchase_status = 'pending' then 'pending-payment'
                    -- Report a claimable admission offer
                    when en.admission_offer_id is not null then 'invitation-approved'
                    -- Report a request awaiting review on approval events
                    when en.invitation_request_status = 'pending'
                        and se.attendee_approval_required then 'pending-approval'
                    -- Report a rejected request on approval events
                    when en.invitation_request_status = 'rejected'
                        and se.attendee_approval_required then 'rejected'
                    -- Report a waitlist entry
                    when en.waitlisted then 'waitlisted'
                    -- Report an elapsed latest offer
                    when en.latest_offer_expired then 'offer-expired'
                    -- Report no enrollment state
                    else 'none'
                end
                from enrollment en
                cross join scoped_event se
            ), 'none') as status
    )
    -- Project the normalized state into the Rust enrollment JSON contract
    select (
        jsonb_build_object(
            'is_checked_in', es.is_checked_in,
            'purchase_amount_minor', (select (ps.purchase).amount_minor from purchase_state ps),
            'purchase_charge_model', (select (ps.purchase).charge_model from purchase_state ps),
            'refund_request_status', (select refund_request_status from enrollment),
            'resume_checkout_url', (
                select (ps.purchase).provider_checkout_url
                from purchase_state ps
                where (ps.purchase).charge_model is distinct from 'external'
            ),
            'status', es.status
        )
        || jsonb_strip_nulls(jsonb_build_object(
            'admission_offer_id', (select admission_offer_id from enrollment),
            'event_ticket_type_id', (select admission_offer_event_ticket_type_id from enrollment),
            'external_payment', (
                select event_purchase_external_payment_json(ps.event, ps.purchase)
                from purchase_state ps
                where (ps.purchase).status = 'pending'
                and (ps.purchase).charge_model = 'external'
            ),
            'refund_rejection_reason', (select refund_rejection_reason from enrollment)
        ))
        || case
            -- Flag organizer invitations
            when es.manually_invited then jsonb_build_object('manually_invited', true)
            -- Omit the flag otherwise
            else '{}'::jsonb
        end
    )::json
    from enrollment_state es;
$$ language sql stable;
