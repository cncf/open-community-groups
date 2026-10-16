-- validate_event_meeting_durations validates automatic meeting durations against provider limits.
create or replace function validate_event_meeting_durations(
    p_event jsonb,
    p_cfg_meeting_limits jsonb default null
)
returns void as $$
declare
    v_duration_minutes int;
    v_max_duration_minutes int;
    v_meeting record;
    v_min_duration_minutes int;
    v_timezone text := p_event->>'timezone';
begin
    -- Check the event and each session that requests an automatic meeting
    for v_meeting in
        select
            'event' as subject,
            p_event->>'ends_at' as ends_at,
            p_event->>'meeting_provider_id' as meeting_provider_id,
            p_event->>'starts_at' as starts_at
        where (p_event->>'meeting_requested')::boolean = true
        union all
        select
            format('session "%s"', s.session->>'name') as subject,
            s.session->>'ends_at' as ends_at,
            s.session->>'meeting_provider_id' as meeting_provider_id,
            s.session->>'starts_at' as starts_at
        from jsonb_array_elements(coalesce(p_event->'sessions', '[]'::jsonb)) as s(session)
        where (s.session->>'meeting_requested')::boolean = true
    loop
        -- Resolve the duration limits configured for the meeting provider
        v_max_duration_minutes := (
            p_cfg_meeting_limits->(v_meeting.meeting_provider_id)->>'max_duration_minutes'
        )::int;
        v_min_duration_minutes := (
            p_cfg_meeting_limits->(v_meeting.meeting_provider_id)->>'min_duration_minutes'
        )::int;

        -- Skip providers without configured limits or schedules without both dates
        if v_max_duration_minutes is null
           or v_min_duration_minutes is null
           or nullif(v_meeting.starts_at, '') is null
           or nullif(v_meeting.ends_at, '') is null
        then
            continue;
        end if;

        -- Measure the duration in whole minutes in the payload timezone
        v_duration_minutes := floor(extract(epoch from (
            (v_meeting.ends_at::timestamp at time zone v_timezone)
            - (v_meeting.starts_at::timestamp at time zone v_timezone)
        )) / 60)::int;

        -- Reject durations outside the provider limits
        if v_duration_minutes < v_min_duration_minutes
           or v_duration_minutes > v_max_duration_minutes
        then
            raise exception '% meeting duration (% minutes) must be between % and % minutes',
                v_meeting.subject,
                v_duration_minutes,
                v_min_duration_minutes,
                v_max_duration_minutes
                using errcode = 'OCG01';
        end if;
    end loop;
end;
$$ language plpgsql;
