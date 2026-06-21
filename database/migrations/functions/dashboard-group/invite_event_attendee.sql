-- Creates an organizer event invitation for a registered or pre-registered user.
create or replace function invite_event_attendee(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_event_id uuid,
    p_user_id uuid,
    p_email text
)
returns uuid as $$
declare
    v_existing_status text;
    v_existing_user_email_verified boolean;
    v_existing_user_registration_status text;
    v_has_registration_questions boolean;
    v_normalized_email text := lower(nullif(btrim(p_email), ''));
    v_registration_questions jsonb;
    v_target_user_id uuid;
begin
    -- Validate invitation target shape
    if (p_user_id is null and v_normalized_email is null)
        or (p_user_id is not null and v_normalized_email is not null) then
        raise exception 'provide exactly one invite target';
    end if;

    -- Lock and validate the event, capturing registration questions for the invitation
    select e.registration_questions
    into v_registration_questions
    from event e
    join "group" g using (group_id)
    where e.event_id = p_event_id
    and e.group_id = p_group_id
    and g.active = true
    and e.deleted = false
    and e.published = true
    and e.canceled = false
    and (
        coalesce(e.ends_at, e.starts_at) is null
        or coalesce(e.ends_at, e.starts_at) >= current_timestamp
    )
    for update of e;

    if not found then
        raise exception 'event not found or inactive';
    end if;

    -- Route invitees through the questions flow when any registration questions exist
    v_has_registration_questions := jsonb_array_length(coalesce(v_registration_questions, '[]'::jsonb)) > 0;

    -- Ticketed events must use the ticketing flow
    if exists (
        select 1
        from event_ticket_type ett
        where ett.event_id = p_event_id
    ) then
        raise exception 'manual invitations are not available for ticketed events';
    end if;

    -- Resolve registered or pre-register email invitee
    if p_user_id is not null then
        select u.user_id
        into v_target_user_id
        from "user" u
        where u.user_id = p_user_id
        and u.registration_status = 'registered'
        and u.email_verified = true;

        if not found then
            raise exception 'registered user not found';
        end if;
    else
        select
            u.email_verified,
            u.registration_status,
            u.user_id
        into
            v_existing_user_email_verified,
            v_existing_user_registration_status,
            v_target_user_id
        from "user" u
        where lower(u.email) = v_normalized_email;

        if not found then
            insert into "user" (
                auth_hash,
                email,
                email_verified,
                registration_status,
                username
            ) values (
                encode(gen_random_bytes(32), 'hex'),
                v_normalized_email,
                false,
                'pre-registered',
                'invited-' || substr(encode(digest(convert_to(v_normalized_email, 'utf8'), 'sha256'), 'hex'), 1, 24)
            )
            returning user_id into v_target_user_id;
        elsif v_existing_user_registration_status = 'registered'
            and v_existing_user_email_verified = false then
            raise exception 'registered user email is not verified';
        end if;
    end if;

    -- Serialize movement between waitlist and attendee invitation state
    perform pg_advisory_xact_lock(hashtext(p_event_id::text), hashtext(v_target_user_id::text));

    -- Reject statuses that should not be invited again
    select ea.status
    into v_existing_status
    from event_attendee ea
    where ea.event_id = p_event_id
    and ea.user_id = v_target_user_id;

    if v_existing_status = 'confirmed' then
        raise exception 'user is already attending this event';
    end if;

    if v_existing_status = 'invitation-pending' then
        raise exception 'user already has a pending event invitation';
    end if;

    if v_existing_status = 'registration-questions-pending' then
        raise exception 'user already has a pending event registration';
    end if;

    if v_existing_status = 'invitation-rejected' then
        raise exception 'user rejected an invitation for this event';
    end if;

    -- Remove waitlist membership before creating the invitation row
    delete from event_waitlist
    where event_id = p_event_id
    and user_id = v_target_user_id;

    -- Reuse canceled rows so organizers can correct mistakes
    if v_existing_status = 'invitation-canceled' then
        update event_attendee
        set
            checked_in = false,
            checked_in_at = null,
            created_at = current_timestamp,
            manually_invited = true,
            registration_answers = null,
            status = case
                when v_has_registration_questions then 'registration-questions-pending'
                else 'invitation-pending'
            end
        where event_id = p_event_id
        and user_id = v_target_user_id;
    else
        insert into event_attendee (event_id, user_id, manually_invited, status)
        values (
            p_event_id,
            v_target_user_id,
            true,
            case
                when v_has_registration_questions then 'registration-questions-pending'
                else 'invitation-pending'
            end
        );
    end if;

    -- Track the invitation
    perform insert_audit_log(
        'event_attendee_invitation_sent',
        p_actor_user_id,
        'user',
        v_target_user_id,
        (select g.alliance_id from "group" g where g.group_id = p_group_id),
        p_group_id,
        p_event_id,
        jsonb_build_object('event_id', p_event_id, 'user_id', v_target_user_id)
    );

    return v_target_user_id;
end;
$$ language plpgsql;
