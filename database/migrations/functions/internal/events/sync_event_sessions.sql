-- Synchronizes the sessions and session speakers of an event with the update
-- payload: existing sessions are updated (their meeting sync state derived
-- from the stored row), new ones inserted, omitted ones removed. The prior
-- event row is null when the event is being created.
create or replace function sync_event_sessions(
    p_event_id uuid,
    p_event jsonb,
    p_before event
)
returns void as $$
declare
    v_processed_session_ids uuid[] := '{}';
    v_session jsonb;
    v_session_before session;
    v_session_ends_at timestamptz;
    v_session_id uuid;
    v_session_meeting_hosts text[];
    v_session_speaker jsonb;
    v_session_starts_at timestamptz;
    v_timezone text := p_event->>'timezone';
begin
    -- Remove every session when the payload omits them
    if p_event->'sessions' is null then
        delete from session_speaker
        where session_id in (select session_id from session where event_id = p_event_id);

        delete from session where event_id = p_event_id;

        return;
    end if;

    -- Upsert each submitted session and replace its speakers
    for v_session in select jsonb_array_elements(p_event->'sessions')
    loop
        v_session_ends_at := (v_session->>'ends_at')::timestamp at time zone v_timezone;
        v_session_meeting_hosts := jsonb_text_array(v_session->'meeting_hosts');
        v_session_starts_at := (v_session->>'starts_at')::timestamp at time zone v_timezone;

        -- Update an existing session from its stored row
        if v_session->>'session_id' is not null then
            v_session_id := (v_session->>'session_id')::uuid;

            -- Load the stored session for the meeting sync checks
            select s.*
            into v_session_before
            from session s
            where s.session_id = v_session_id
            and s.event_id = p_event_id;

            -- Reject sessions that belong to another event
            if not found then
                raise exception 'session % not found for event %', v_session_id, p_event_id using errcode = 'OCG01';
            end if;

            -- Update the session unconditionally so the session bounds trigger
            -- re-validates it against the current event dates
            update session set
                cfs_submission_id = nullif(v_session->>'cfs_submission_id', '')::uuid,
                description = nullif(v_session->>'description', ''),
                ends_at = v_session_ends_at,
                location = nullif(v_session->>'location', ''),
                meeting_hosts = v_session_meeting_hosts,
                meeting_in_sync = case
                    -- Preserve pending meeting work while the meeting stays requested
                    when v_session_before.meeting_in_sync = false
                         and (v_session->>'meeting_requested')::boolean is distinct from false
                    then false
                    -- Recompute meeting synchronization for other updates
                    else is_session_meeting_in_sync(v_session_before, v_session, p_before, p_event)
                end,
                meeting_join_instructions = nullif(v_session->>'meeting_join_instructions', ''),
                meeting_join_url = nullif(v_session->>'meeting_join_url', ''),
                meeting_provider_id = nullif(v_session->>'meeting_provider_id', ''),
                meeting_recording_published = coalesce(
                    (v_session->>'meeting_recording_published')::boolean,
                    v_session_before.meeting_recording_published,
                    false
                ),
                meeting_recording_url = nullif(v_session->>'meeting_recording_url', ''),
                meeting_requested = (v_session->>'meeting_requested')::boolean,
                name = v_session->>'name',
                session_kind_id = v_session->>'kind',
                starts_at = v_session_starts_at
            where session_id = v_session_id;

            -- Replace the speakers below from the payload
            delete from session_speaker where session_id = v_session_id;

        -- Insert a new session, starting requested meetings out of sync
        else
            insert into session (
                event_id,
                name,
                description,
                starts_at,
                ends_at,
                cfs_submission_id,
                session_kind_id,
                location,
                meeting_hosts,
                meeting_in_sync,
                meeting_join_instructions,
                meeting_join_url,
                meeting_provider_id,
                meeting_recording_published,
                meeting_recording_url,
                meeting_requested
            ) values (
                p_event_id,
                v_session->>'name',
                nullif(v_session->>'description', ''),
                v_session_starts_at,
                v_session_ends_at,
                nullif(v_session->>'cfs_submission_id', '')::uuid,
                v_session->>'kind',
                nullif(v_session->>'location', ''),
                v_session_meeting_hosts,
                case
                    -- Start requested meetings out of sync so provisioning runs
                    when (v_session->>'meeting_requested')::boolean = true then false
                    -- Leave unrequested meetings without sync state
                    else null
                end,
                nullif(v_session->>'meeting_join_instructions', ''),
                nullif(v_session->>'meeting_join_url', ''),
                nullif(v_session->>'meeting_provider_id', ''),
                coalesce((v_session->>'meeting_recording_published')::boolean, false),
                nullif(v_session->>'meeting_recording_url', ''),
                (v_session->>'meeting_requested')::boolean
            )
            returning session_id into v_session_id;
        end if;

        v_processed_session_ids := array_append(v_processed_session_ids, v_session_id);

        -- Insert the submitted speakers
        for v_session_speaker in select jsonb_array_elements(v_session->'speakers')
        loop
            insert into session_speaker (session_id, user_id, featured)
            values (
                v_session_id,
                (v_session_speaker->>'user_id')::uuid,
                (v_session_speaker->>'featured')::boolean
            );
        end loop;
    end loop;

    -- Remove sessions omitted from the payload
    delete from session_speaker
    where session_id in (
        select s.session_id
        from session s
        where s.event_id = p_event_id
        and not (s.session_id = any(v_processed_session_ids))
    );

    delete from session
    where event_id = p_event_id
    and not (session_id = any(v_processed_session_ids));
end;
$$ language plpgsql;
