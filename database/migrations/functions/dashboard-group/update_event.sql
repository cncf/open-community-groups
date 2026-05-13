-- update_event updates an existing event in the database.
create or replace function update_event(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_event_id uuid,
    p_event jsonb,
    p_cfg_max_participants jsonb default null
)
returns json as $$
declare
    v_discount_codes jsonb;
    v_effective_capacity int;
    v_event_attendee_approval_required boolean := coalesce((p_event->>'attendee_approval_required')::boolean, false);
    v_event_before jsonb;
    v_event_capacity_before int;
    v_event_location geography;
    v_event_meeting_hosts text[];
    v_event_photos_urls text[];
    v_event_reminder_enabled boolean := coalesce((p_event->>'event_reminder_enabled')::boolean, true);
    v_event_tags text[];
    v_event_waitlist_enabled boolean := coalesce((p_event->>'waitlist_enabled')::boolean, false);
    v_has_existing_attendees boolean;
    v_has_new_waitlist_capacity boolean;
    v_has_pending_invitation_requests boolean;
    v_has_waitlist_entries boolean;
    v_is_promotable_event boolean;
    v_new_capacity int := (p_event->>'capacity')::int;
    v_new_ends_at timestamptz;
    v_new_starts_at timestamptz;
    v_payment_currency_code text;
    v_promoted_user_ids uuid[] := array[]::uuid[];
    v_ticket_capacity int;
    v_ticket_types jsonb;
    v_timezone text := p_event->>'timezone';
    v_was_ticketed boolean;
begin
    -- Load the locked event state used by the update flow
    select
        get_event_full(g.community_id, p_group_id, p_event_id)::jsonb
    into
        v_event_before
    from "group" g
    join event e on e.group_id = g.group_id
    where g.group_id = p_group_id
    and e.event_id = p_event_id
    and e.deleted = false
    and e.canceled = false
    for update of e;

    if v_event_before is null then
        raise exception 'event not found or inactive';
    end if;

    -- Parse payload values used across the update flow
    v_event_capacity_before := (v_event_before->>'capacity')::int;
    v_event_location := case
        when (p_event->>'latitude') is not null
             and (p_event->>'longitude') is not null
        then ST_SetSRID(
            ST_MakePoint(
                (p_event->>'longitude')::float,
                (p_event->>'latitude')::float
            ),
            4326
        )::geography
        else null
    end;
    v_event_meeting_hosts := case
        when p_event->'meeting_hosts' is not null
        then array(select jsonb_array_elements_text(p_event->'meeting_hosts'))
        else null
    end;
    v_event_photos_urls := case
        when p_event->'photos_urls' is not null
        then array(select jsonb_array_elements_text(p_event->'photos_urls'))
        else null
    end;
    v_event_tags := case
        when p_event->'tags' is not null
        then array(select jsonb_array_elements_text(p_event->'tags'))
        else null
    end;

    -- Resolve ticketing values and the effective event capacity
    v_discount_codes := case
        when p_event ? 'discount_codes'
        then nullif(p_event->'discount_codes', 'null'::jsonb)
        else v_event_before->'discount_codes'
    end;
    v_ticket_types := case
        when p_event ? 'ticket_types'
        then nullif(p_event->'ticket_types', 'null'::jsonb)
        else v_event_before->'ticket_types'
    end;
    v_ticket_capacity := get_event_ticket_capacity(v_ticket_types);
    v_effective_capacity := coalesce(v_ticket_capacity, v_new_capacity);
    v_payment_currency_code := case
        when p_event ? 'payment_currency_code'
        then nullif(p_event->>'payment_currency_code', '')
        else nullif(v_event_before->>'payment_currency_code', '')
    end;

    -- Load current event state required by registration and ticketing guards
    v_has_existing_attendees := exists(
        select 1
        from event_attendee
        where event_id = p_event_id
    );
    v_has_pending_invitation_requests := exists(
        select 1
        from event_invitation_request
        where event_id = p_event_id
        and status = 'pending'
    );
    v_has_waitlist_entries := exists(
        select 1
        from event_waitlist
        where event_id = p_event_id
    );
    v_was_ticketed := jsonb_array_length(coalesce(v_event_before->'ticket_types', '[]'::jsonb)) > 0;

    -- Enforce attendee approval transition rules
    if v_event_attendee_approval_required = false and v_has_pending_invitation_requests then
        raise exception 'approval-required events with pending invitation requests cannot disable approval';
    end if;

    -- Block approval-required attendance while queued users exist
    if v_event_attendee_approval_required = true and v_has_waitlist_entries then
        raise exception 'approval-required events cannot have existing waitlist entries';
    end if;

    -- Enforce ticketing transition rules
    if v_ticket_types is not null and not v_was_ticketed and v_has_existing_attendees then
        raise exception 'ticketed events require an empty attendee list';
    end if;

    if v_ticket_types is not null and v_has_waitlist_entries then
        raise exception 'ticketed events cannot have existing waitlist entries';
    end if;

    -- Validate enrollment and ticketing payload rules
    perform validate_event_enrollment_payload(
        v_event_attendee_approval_required,
        v_ticket_types,
        v_event_waitlist_enabled
    );

    perform validate_event_ticketing_payload(
        v_discount_codes,
        v_payment_currency_code,
        v_ticket_types,
        v_event_waitlist_enabled
    );

    -- Parse event timestamps once for validation and row updates
    if p_event->>'ends_at' is not null then
        v_new_ends_at := (p_event->>'ends_at')::timestamp at time zone v_timezone;
    end if;

    if p_event->>'starts_at' is not null then
        v_new_starts_at := (p_event->>'starts_at')::timestamp at time zone v_timezone;
    end if;

    -- Precompute promotion conditions for waitlist processing
    v_has_new_waitlist_capacity := (
        -- Removing the capacity limit makes every queued seat available
        (
            v_new_capacity is null
            and v_event_capacity_before is not null
        )
        -- Increasing a bounded capacity opens additional attendee seats
        or (
            v_new_capacity is not null
            and (
                v_event_capacity_before is null
                or v_new_capacity > v_event_capacity_before
            )
        )
    );

    -- Only published events that are still upcoming or dateless can promote the waitlist
    v_is_promotable_event := (v_event_before->>'published')::boolean = true
        and (
            coalesce(v_new_ends_at, v_new_starts_at) is null
            or coalesce(v_new_ends_at, v_new_starts_at) >= current_timestamp
        );

    -- Validate update-specific event and session date rules
    perform validate_update_event_dates(p_event, v_event_before);

    -- Validate capacity
    perform validate_event_capacity(
        p_event,
        p_cfg_max_participants,
        p_existing_event_id => p_event_id,
        p_effective_capacity => v_effective_capacity
    );

    -- Validate CFS labels rules
    perform validate_event_cfs_labels_payload(p_event->'cfs_labels');

    -- Update event
    update event set
        name = p_event->>'name',
        description = p_event->>'description',
        timezone = p_event->>'timezone',
        event_category_id = (p_event->>'category_id')::uuid,
        event_kind_id = p_event->>'kind_id',

        attendee_approval_required = v_event_attendee_approval_required,
        banner_mobile_url = nullif(p_event->>'banner_mobile_url', ''),
        banner_url = nullif(p_event->>'banner_url', ''),
        capacity = v_effective_capacity,
        cfs_description = nullif(p_event->>'cfs_description', ''),
        cfs_enabled = (p_event->>'cfs_enabled')::boolean,
        cfs_ends_at = (p_event->>'cfs_ends_at')::timestamp at time zone v_timezone,
        cfs_starts_at = (p_event->>'cfs_starts_at')::timestamp at time zone v_timezone,
        description_short = nullif(p_event->>'description_short', ''),
        ends_at = v_new_ends_at,
        event_reminder_enabled = v_event_reminder_enabled,
        -- Mark reminder as evaluated when update moves start time inside the 24-hour window
        event_reminder_evaluated_for_starts_at = case
            when v_event_reminder_enabled = true
                 and event_reminder_sent_at is null
                 and starts_at is distinct from v_new_starts_at
                 and (
                     starts_at is null
                     or starts_at <= current_timestamp
                     or starts_at > current_timestamp + interval '24 hours'
                 )
                 and v_new_starts_at is not null
                 and v_new_starts_at > current_timestamp
                 and v_new_starts_at <= current_timestamp + interval '24 hours'
            then v_new_starts_at
            else event_reminder_evaluated_for_starts_at
        end,
        location = v_event_location,
        logo_url = nullif(p_event->>'logo_url', ''),
        meeting_hosts = v_event_meeting_hosts,
        meeting_in_sync = case
            when (v_event_before->>'meeting_in_sync')::boolean = false
                 and (p_event->>'meeting_requested')::boolean is distinct from false
            then false
            else is_event_meeting_in_sync(v_event_before, p_event)
        end,
        meeting_join_instructions = nullif(p_event->>'meeting_join_instructions', ''),
        meeting_join_url = nullif(p_event->>'meeting_join_url', ''),
        meeting_provider_id = p_event->>'meeting_provider_id',
        meeting_recording_published = coalesce(
            (p_event->>'meeting_recording_published')::boolean,
            (v_event_before->>'meeting_recording_published')::boolean,
            false
        ),
        meeting_recording_requested = coalesce((p_event->>'meeting_recording_requested')::boolean, true),
        meeting_recording_url = nullif(p_event->>'meeting_recording_url', ''),
        meeting_requested = (p_event->>'meeting_requested')::boolean,
        meetup_url = nullif(p_event->>'meetup_url', ''),
        payment_currency_code = v_payment_currency_code,
        photos_urls = v_event_photos_urls,
        registration_required = (p_event->>'registration_required')::boolean,
        starts_at = v_new_starts_at,
        tags = v_event_tags,
        venue_address = nullif(p_event->>'venue_address', ''),
        venue_city = nullif(p_event->>'venue_city', ''),
        venue_country_code = nullif(p_event->>'venue_country_code', ''),
        venue_country_name = nullif(p_event->>'venue_country_name', ''),
        venue_name = nullif(p_event->>'venue_name', ''),
        venue_state = nullif(p_event->>'venue_state', ''),
        venue_zip_code = nullif(p_event->>'venue_zip_code', ''),
        waitlist_enabled = case
            when v_ticket_types is not null then false
            else v_event_waitlist_enabled
        end
    where event_id = p_event_id
    and group_id = p_group_id
    and deleted = false
    and canceled = false;

    -- Promote waitlisted users when the update creates new attendee capacity
    if v_ticket_types is null and v_has_new_waitlist_capacity and v_is_promotable_event then
        select promote_event_waitlist(p_event_id)
        into v_promoted_user_ids;
    end if;

    -- Synchronize normalized ticketing data after updating the event row
    perform sync_event_discount_codes(p_event_id, v_discount_codes);
    perform sync_event_ticket_types(p_event_id, v_ticket_types);

    -- Synchronize event CFS labels
    perform sync_event_cfs_labels(p_event_id, p_event->'cfs_labels');

    -- Delete existing hosts, sponsors, sessions and speakers
    delete from event_host where event_id = p_event_id;
    delete from event_speaker where event_id = p_event_id;
    delete from event_sponsor where event_id = p_event_id;

    -- Insert event hosts
    if p_event->'hosts' is not null then
        insert into event_host (event_id, user_id)
        select p_event_id, host.user_id::uuid
        from jsonb_array_elements_text(p_event->'hosts') as host(user_id);
    end if;

    -- Insert event speakers
    if p_event->'speakers' is not null then
        insert into event_speaker (event_id, user_id, featured)
        select p_event_id, speaker.user_id, speaker.featured
        from jsonb_to_recordset(p_event->'speakers') as speaker(featured boolean, user_id uuid);
    end if;

    -- Insert event sponsors with per-event level
    if p_event->'sponsors' is not null then
        insert into event_sponsor (event_id, group_sponsor_id, level)
        select p_event_id, sponsor.group_sponsor_id, sponsor.level
        from jsonb_to_recordset(p_event->'sponsors') as sponsor(group_sponsor_id uuid, level text);
    end if;

    -- Synchronize event sessions and speakers
    perform sync_event_sessions(p_event_id, p_event, v_event_before);

    -- Track the updated event
    perform insert_audit_log(
        'event_updated',
        p_actor_user_id,
        'event',
        p_event_id,
        (
            select g.community_id
            from event e
            join "group" g on g.group_id = e.group_id
            where e.event_id = p_event_id
        ),
        p_group_id,
        p_event_id
    );

    return to_json(v_promoted_user_ids);
end;
$$ language plpgsql;
