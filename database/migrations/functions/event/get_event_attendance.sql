-- Get a user's attendance details for an event, including check-in status.
create or replace function get_event_attendance(
    p_community_id uuid,
    p_event_id uuid,
    p_user_id uuid
) returns json as $$
    with scoped_event as (
        select
            e.attendee_approval_required,
            e.event_id
        from event e
        join "group" g on g.group_id = e.group_id
        where e.event_id = p_event_id
        and g.community_id = p_community_id
        and g.active = true
        and e.deleted = false
        and e.published = true
        and e.canceled = false
        and (
            -- Keep started events without an end time readable for check-in and status views
            -- even though attend_event and leave_event treat them as inactive for mutations
            e.ends_at is null
            or e.ends_at >= current_timestamp
        )
    ),
    attendance_state as (
        select
            coalesce(
                (
                    select bool_and(ea.checked_in)
                    from event_attendee ea
                    where ea.event_id = p_event_id
                    and ea.user_id = p_user_id
                    and exists (select 1 from scoped_event)
                ),
                false
            ) as is_checked_in,
            case
                when exists (
                    select 1
                    from event_attendee ea
                    where ea.event_id = p_event_id
                    and ea.user_id = p_user_id
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
        json_build_object(
            'is_checked_in', is_checked_in,
            'purchase_amount_minor', (select amount_minor from purchase_state),
            'refund_request_status', (select refund_request_status from refund_request_state),
            'resume_checkout_url', (select provider_checkout_url from purchase_state),
            'status', status
        )
    from attendance_state;
$$ language sql;
