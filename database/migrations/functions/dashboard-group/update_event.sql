-- update_event updates an existing event in the database.
create or replace function update_event(
    p_group_id uuid,
    p_event_id uuid,
    p_event jsonb,
    p_cfg_max_participants jsonb default null
)
returns void as $$
declare
    v_event_location geography;
    v_event_meeting_hosts text[];
    v_event_photos_urls text[];
    v_event_before jsonb;
    v_event_reminder_enabled boolean;
    v_event_tags text[];
    v_new_ends_at timestamptz;
    v_new_starts_at timestamptz;
    v_timezone text := p_event->>'timezone';
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

    -- Precompute derived values used across the update flow
    v_event_location := case
        when (p_event->>'latitude') is not null and (p_event->>'longitude') is not null
        then ST_SetSRID(ST_MakePoint((p_event->>'longitude')::float, (p_event->>'latitude')::float), 4326)::geography
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
    v_event_reminder_enabled := coalesce((p_event->>'event_reminder_enabled')::boolean, true);
    v_event_tags := case
        when p_event->'tags' is not null
        then array(select jsonb_array_elements_text(p_event->'tags'))
        else null
    end;

    -- Parse event timestamps once for validation and row updates
    if p_event->>'ends_at' is not null then
        v_new_ends_at := (p_event->>'ends_at')::timestamp at time zone v_timezone;
    end if;

    if p_event->>'starts_at' is not null then
        v_new_starts_at := (p_event->>'starts_at')::timestamp at time zone v_timezone;
    end if;

    -- Validate update-specific event and session date rules
    perform validate_update_event_dates(p_event, v_event_before);

    -- Validate capacity
    perform validate_event_capacity(
        p_event,
        p_cfg_max_participants,
        p_existing_event_id => p_event_id
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

        banner_mobile_url = nullif(p_event->>'banner_mobile_url', ''),
        banner_url = nullif(p_event->>'banner_url', ''),
        capacity = (p_event->>'capacity')::int,
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
        meeting_join_url = nullif(p_event->>'meeting_join_url', ''),
        meeting_provider_id = p_event->>'meeting_provider_id',
        meeting_recording_url = nullif(p_event->>'meeting_recording_url', ''),
        meeting_requested = (p_event->>'meeting_requested')::boolean,
        meetup_url = nullif(p_event->>'meetup_url', ''),
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
        venue_zip_code = nullif(p_event->>'venue_zip_code', '')
    where event_id = p_event_id
    and group_id = p_group_id
    and deleted = false
    and canceled = false;

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
end;
$$ language plpgsql;
