-- sync_event_sessions synchronizes an event's sessions.
create or replace function sync_event_sessions(
    p_event_id uuid,
    p_event jsonb,
    p_event_before jsonb
)
returns void as $$
declare
    v_processed_session_ids uuid[] := '{}';
    v_session jsonb;
    v_session_before jsonb;
    v_session_ends_at timestamptz;
    v_session_id uuid;
    v_session_meeting_hosts text[];
    v_session_speaker jsonb;
    v_session_starts_at timestamptz;
    v_speaker_featured boolean;
    v_speaker_id uuid;
    v_timezone text := p_event->>'timezone';
begin
    -- Upsert sessions and replace their speakers from the payload
    if p_event->'sessions' is not null then
        for v_session in select jsonb_array_elements(p_event->'sessions')
        loop
            v_session_ends_at := (v_session->>'ends_at')::timestamp at time zone v_timezone;
            v_session_meeting_hosts := case
                when v_session->'meeting_hosts' is not null
                then array(select jsonb_array_elements_text(v_session->'meeting_hosts'))
                else null
            end;
            v_session_starts_at := (v_session->>'starts_at')::timestamp at time zone v_timezone;

            if v_session->>'session_id' is not null then
                v_session_id := (v_session->>'session_id')::uuid;

                -- Load the previous session snapshot for sync checks
                select sess
                into v_session_before
                from jsonb_each(p_event_before->'sessions') as day(day, sessions)
                cross join lateral jsonb_array_elements(sessions) as sess
                where sess->>'session_id' = v_session_id::text
                limit 1;

                update session set
                    cfs_submission_id = nullif(v_session->>'cfs_submission_id', '')::uuid,
                    description = nullif(v_session->>'description', ''),
                    ends_at = v_session_ends_at,
                    location = nullif(v_session->>'location', ''),
                    meeting_hosts = v_session_meeting_hosts,
                    meeting_in_sync = case
                        when (v_session_before->>'meeting_in_sync')::boolean = false
                             and (v_session->>'meeting_requested')::boolean is distinct from false
                        then false
                        else is_session_meeting_in_sync(v_session_before, v_session, p_event_before, p_event)
                    end,
                    meeting_join_instructions = nullif(v_session->>'meeting_join_instructions', ''),
                    meeting_join_url = nullif(v_session->>'meeting_join_url', ''),
                    meeting_provider_id = nullif(v_session->>'meeting_provider_id', ''),
                    meeting_recording_url = nullif(v_session->>'meeting_recording_url', ''),
                    meeting_requested = (v_session->>'meeting_requested')::boolean,
                    name = v_session->>'name',
                    session_kind_id = v_session->>'kind',
                    starts_at = v_session_starts_at
                where session_id = v_session_id
                and event_id = p_event_id;

                if not found then
                    raise exception 'session % not found for event %', v_session_id, p_event_id;
                end if;

                delete from session_speaker where session_id = v_session_id;
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
                        when (v_session->>'meeting_requested')::boolean = true then false
                        else null
                    end,
                    nullif(v_session->>'meeting_join_instructions', ''),
                    nullif(v_session->>'meeting_join_url', ''),
                    nullif(v_session->>'meeting_provider_id', ''),
                    nullif(v_session->>'meeting_recording_url', ''),
                    (v_session->>'meeting_requested')::boolean
                )
                returning session_id into v_session_id;
            end if;

            v_processed_session_ids := array_append(v_processed_session_ids, v_session_id);

            if v_session->'speakers' is not null then
                for v_session_speaker in select jsonb_array_elements(v_session->'speakers')
                loop
                    v_speaker_featured := (v_session_speaker->>'featured')::boolean;
                    v_speaker_id := (v_session_speaker->>'user_id')::uuid;

                    insert into session_speaker (session_id, user_id, featured)
                    values (v_session_id, v_speaker_id, v_speaker_featured);
                end loop;
            end if;
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
    else
        -- Remove all sessions when the payload omits them
        delete from session_speaker
        where session_id in (select session_id from session where event_id = p_event_id);

        delete from session where event_id = p_event_id;
    end if;
end;
$$ language plpgsql;
