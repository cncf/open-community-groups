-- Resolves an attendee credential and returns the organizer scan result.
create or replace function check_in_attendee_by_code(
    p_actor_user_id uuid,
    p_check_in_code uuid,
    p_community_id uuid,
    p_event_id uuid,
    p_group_id uuid
)
returns json as $$
declare
    v_attendee record;
    v_checked_in boolean;
begin
    -- Validate that the event is available in the selected group
    perform 1
    from event e
    join "group" g using (group_id)
    where e.event_id = p_event_id
    and e.group_id = p_group_id
    and g.community_id = p_community_id
    and g.active = true
    and g.deleted = false
    and e.canceled = false
    and e.deleted = false
    and e.published = true
    and e.starts_at is not null
    and current_timestamp < coalesce(
        e.ends_at,
        (
            date_trunc('day', e.starts_at at time zone e.timezone)
            + interval '1 day'
        ) at time zone e.timezone
    )
    for update of e;

    -- Reject unavailable events before resolving credentials
    if not found then
        raise exception 'event unavailable for check-in';
    end if;

    -- Resolve the credential and attendee display context
    select
        ea.status,
        u.name,
        u.photo_url,
        coalesce(purchase.ticket_title, offer.ticket_title) as ticket_title,
        u.user_id,
        u.username
    into v_attendee
    from event_attendee ea
    join "user" u using (user_id)
    left join lateral (
        select ep.ticket_title
        from event_purchase ep
        where ep.event_id = ea.event_id
        and ep.user_id = ea.user_id
        and ep.status in (
            'completed',
            'refund-pending',
            'refund-recovery-pending',
            'refund-requested',
            'refunded'
        )
        order by ep.created_at desc, ep.event_purchase_id desc
        limit 1
    ) purchase on true
    left join lateral (
        select coalesce(ao.ticket_title, ett.title) as ticket_title
        from admission_offer ao
        left join event_ticket_type ett using (event_ticket_type_id)
        where ao.event_id = ea.event_id
        and ao.user_id = ea.user_id
        and ao.status = 'completed'
        order by ao.created_at desc, ao.admission_offer_id desc
        limit 1
    ) offer on true
    where ea.check_in_code = p_check_in_code
    and ea.event_id = p_event_id
    for update of ea;

    -- Reject credentials that do not belong to the selected event
    if not found then
        raise exception 'check-in credential not found';
    end if;

    -- Reject credentials whose attendance is no longer confirmed
    if v_attendee.status <> 'confirmed' then
        raise exception 'attendance is not confirmed';
    end if;

    -- Apply the shared atomic transition and audit behavior
    v_checked_in := check_in_event(
        p_actor_user_id,
        p_community_id,
        p_event_id,
        v_attendee.user_id
    );

    -- Return the stable scanner response
    return json_strip_nulls(json_build_object(
        'attendee', json_build_object(
            'username', v_attendee.username,

            'name', v_attendee.name,
            'photo_url', v_attendee.photo_url
        ),
        'checked_in_at', (
            select floor(extract(epoch from ea.checked_in_at))
            from event_attendee ea
            where ea.event_id = p_event_id
            and ea.user_id = v_attendee.user_id
        ),
        'outcome', case
            -- Report whether this scan performed the transition
            when v_checked_in then 'checked-in'
            -- Report an idempotent duplicate scan
            else 'already-checked-in'
        end,
        'ticket_title', v_attendee.ticket_title
    ));
end;
$$ language plpgsql;
