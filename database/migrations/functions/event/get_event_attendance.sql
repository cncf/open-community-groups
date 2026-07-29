-- Get a user's attendance details for an event, including check-in status.
create or replace function get_event_attendance(
    p_community_id uuid,
    p_event_id uuid,
    p_user_id uuid
) returns json as $$
    with scoped_event as (
        select
            e.attendee_approval_required,
            e.event_id,
            e.registration_questions
        from event e
        join "group" g on g.group_id = e.group_id
        where e.event_id = p_event_id
        and g.community_id = p_community_id
        and g.active = true
        and e.deleted = false
        and e.published = true
        and (
            -- Keep started events without an end time readable for check-in and status views
            -- even though attend_event and leave_event treat them as inactive for mutations
            e.canceled = true
            or e.ends_at is null
            or e.ends_at >= current_timestamp
        )
    ),
    active_offer_state as (
        select
            ao.admission_offer_id,
            ao.event_ticket_type_id,
            ao.source,
            ao.status
        from admission_offer ao
        where ao.event_id = p_event_id
        and ao.user_id = p_user_id
        and ao.status in ('checkout_pending', 'pending')
        and (ao.expires_at is null or ao.expires_at > current_timestamp)
        and not exists (
            select 1
            from event_purchase ep
            where ep.admission_offer_id = ao.admission_offer_id
            and ep.status in (
                'refund-pending',
                'refund-recovery-pending',
                'refund-requested'
            )
        )
        and exists (select 1 from scoped_event)
        order by ao.created_at desc, ao.admission_offer_id desc
        limit 1
    ),
    latest_offer_state as (
        select
            (
                ao.status = 'expired'
                or (
                    ao.status in ('checkout_pending', 'pending')
                    and ao.expires_at is not null
                    and ao.expires_at <= current_timestamp
                )
            ) as is_expired
        from admission_offer ao
        where ao.event_id = p_event_id
        and ao.user_id = p_user_id
        and exists (select 1 from scoped_event)
        order by ao.created_at desc, ao.admission_offer_id desc
        limit 1
    ),
    attendance_state as (
        select
            coalesce(
                (
                    select bool_and(ea.checked_in)
                    from event_attendee ea
                    where ea.event_id = p_event_id
                    and ea.user_id = p_user_id
                    and ea.status = 'confirmed'
                    and exists (select 1 from scoped_event)
                ),
                false
            ) as is_checked_in,
            coalesce(
                (
                    select bool_or(ea.manually_invited)
                    from event_attendee ea
                    where ea.event_id = p_event_id
                    and ea.user_id = p_user_id
                    and exists (select 1 from scoped_event)
                ),
                false
            )
            or exists (
                select 1
                from active_offer_state aos
                where aos.source = 'organizer_invitation'
            ) as manually_invited,
            case
                when exists (
                    select 1
                    from active_offer_state aos
                    where aos.source = 'organizer_invitation'
                    and aos.status = 'pending'
                    and exists (
                        select 1
                        from scoped_event se
                        where aos.event_ticket_type_id is null
                        and jsonb_array_length(
                            coalesce(se.registration_questions, '[]'::jsonb)
                        ) > 0
                    )
                ) then 'registration-questions-pending'
                when exists (
                    select 1
                    from event_attendee ea
                    where ea.event_id = p_event_id
                    and ea.user_id = p_user_id
                    and ea.status = 'confirmed'
                    and exists (select 1 from scoped_event)
                ) then 'attendee'
                when exists (
                    select 1
                    from event_purchase ep
                    where ep.event_id = p_event_id
                    and ep.user_id = p_user_id
                    and ep.status = 'pending'
                    and ep.hold_expires_at > current_timestamp
                    and exists (select 1 from scoped_event)
                ) then 'pending-payment'
                when exists (select 1 from active_offer_state) then 'invitation-approved'
                when exists (
                    select 1
                    from event_attendee ea
                    where ea.event_id = p_event_id
                    and ea.user_id = p_user_id
                    and ea.manually_invited = true
                    and ea.status = 'invitation-pending'
                    and exists (select 1 from scoped_event)
                ) then 'invitation-approved'
                when exists (
                    select 1
                    from event_attendee ea
                    where ea.event_id = p_event_id
                    and ea.user_id = p_user_id
                    and ea.status = 'registration-questions-pending'
                    and exists (select 1 from scoped_event)
                ) then 'registration-questions-pending'
                when exists (
                    select 1
                    from event_invitation_request eir
                    where eir.event_id = p_event_id
                    and eir.user_id = p_user_id
                    and eir.status = 'pending'
                    and exists (
                        select 1
                        from scoped_event se
                        where se.attendee_approval_required = true
                    )
                ) then 'pending-approval'
                when exists (
                    select 1
                    from event_invitation_request eir
                    where eir.event_id = p_event_id
                    and eir.user_id = p_user_id
                    and eir.status = 'accepted'
                    and not exists (
                        select 1
                        from admission_offer ao
                        where ao.event_id = p_event_id
                        and ao.user_id = p_user_id
                        and ao.source = 'approval'
                    )
                    and exists (
                        select 1
                        from scoped_event se
                        where se.attendee_approval_required = true
                    )
                ) then 'invitation-approved'
                when exists (
                    select 1
                    from event_invitation_request eir
                    where eir.event_id = p_event_id
                    and eir.user_id = p_user_id
                    and eir.status = 'rejected'
                    and exists (
                        select 1
                        from scoped_event se
                        where se.attendee_approval_required = true
                    )
                ) then 'rejected'
                when exists (
                    select 1
                    from event_waitlist ew
                    where ew.event_id = p_event_id
                    and ew.user_id = p_user_id
                    and exists (select 1 from scoped_event)
                ) then 'waitlisted'
                when exists (
                    select 1
                    from latest_offer_state los
                    where los.is_expired
                ) then 'offer-expired'
                else 'none'
            end as status
    ),
    purchase_state as (
        select
            ep.event_purchase_id,
            ep.amount_minor,
            ep.provider_checkout_url
        from event_purchase ep
        where ep.event_id = p_event_id
        and ep.user_id = p_user_id
        and (
            ep.status in ('completed', 'refund-requested')
            or (ep.status = 'pending' and ep.hold_expires_at > current_timestamp)
        )
        and exists (select 1 from scoped_event)
        order by
            case when ep.status = 'pending' then 0 else 1 end,
            ep.created_at desc,
            ep.event_purchase_id desc
        limit 1
    ),
    refund_request_state as (
        select
            err.status as refund_request_status
        from event_refund_request err
        join purchase_state ps on ps.event_purchase_id = err.event_purchase_id
        where err.status in ('approved', 'approving', 'pending', 'rejected')
        and exists (select 1 from scoped_event)
        order by err.created_at desc, err.event_refund_request_id desc
        limit 1
    )
    select
        (
            jsonb_build_object(
                'is_checked_in', is_checked_in,
                'purchase_amount_minor', (select amount_minor from purchase_state),
                'refund_request_status', (select refund_request_status from refund_request_state),
                'resume_checkout_url', (select provider_checkout_url from purchase_state),
                'status', status
            )
            || jsonb_strip_nulls(jsonb_build_object(
                'admission_offer_id',
                (select admission_offer_id from active_offer_state),
                'event_ticket_type_id',
                (select event_ticket_type_id from active_offer_state)
            ))
            || case
                when manually_invited then jsonb_build_object('manually_invited', true)
                else '{}'::jsonb
            end
        )::json
    from attendance_state;
$$ language sql;
