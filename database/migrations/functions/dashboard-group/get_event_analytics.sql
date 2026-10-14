-- Returns the analytics of an event owned by a group as a JSON object.
--
-- The lifecycle range runs in UTC days from the publication day to the
-- earlier of today and the effective event end; it is null when the event is
-- unpublished or was published after it ended. Markers are limited to the
-- range and announcements to the 50 most recent ones. Ticket statistics are
-- only reported for paid events.
create or replace function get_event_analytics(
    p_group_id uuid,
    p_event_id uuid
)
returns json as $$
declare
    v_end_day date;
    v_event event;
    v_is_paid boolean;
    v_start_day date;
begin
    -- Load the event owned by the group
    select e.*
    into v_event
    from event e
    where e.event_id = p_event_id
    and e.group_id = p_group_id
    and e.deleted = false;

    -- Report nothing for missing, foreign or deleted events
    if not found then
        return null;
    end if;

    -- Resolve the lifecycle range in UTC days
    v_start_day := (v_event.published_at at time zone 'UTC')::date;
    v_end_day := least(
        (current_timestamp at time zone 'UTC')::date,
        (event_effective_ends_at(v_event) at time zone 'UTC')::date
    );

    -- Drop the range when publication does not precede the event end
    if v_start_day is null or v_start_day > v_end_day then
        v_end_day := null;
        v_start_day := null;
    end if;

    -- Resolve whether the event sells paid tickets
    v_is_paid := is_event_paid_capable(v_event.event_id);

    -- Compose the event, range, markers and section statistics
    return (
        with markers as (
            select marker.kind, marker.ts
            from (
                values
                    ('event-start', v_event.starts_at),
                    ('published', v_event.published_at),
                    ('registration-closes', v_event.registration_ends_at),
                    ('registration-opens', v_event.registration_starts_at),
                    ('reminder-sent', v_event.event_reminder_sent_at)
            ) as marker(kind, ts)
            where (marker.ts at time zone 'UTC')::date between v_start_day and v_end_day
        ),
        announcements as (
            select
                cn.created_at as ts,
                row_number() over (
                    order by cn.created_at desc, cn.custom_notification_id desc
                ) as rank
            from custom_notification cn
            where cn.event_id = v_event.event_id
            and (cn.created_at at time zone 'UTC')::date between v_start_day and v_end_day
        ),
        all_markers as (
            select m.kind, m.ts
            from markers m

            union all

            select 'announcement' as kind, a.ts
            from announcements a
            where a.rank <= 50
        )
        select json_build_object(
            'audience', stats_event_audience(v_event),
            'check_ins', stats_event_check_ins(v_event),
            'enrollment', stats_event_enrollment(v_event),
            'event', json_build_object(
                'canceled', v_event.canceled,
                'is_paid', v_is_paid,
                'published', v_event.published,
                'timezone', v_event.timezone,

                'capacity', v_event.capacity,
                'ends_at', epoch_seconds(v_event.ends_at),
                'published_at', epoch_seconds(v_event.published_at),
                'registration_ends_at', epoch_seconds(v_event.registration_ends_at),
                'registration_starts_at', epoch_seconds(v_event.registration_starts_at),
                'starts_at', epoch_seconds(v_event.starts_at)
            ),
            'markers', coalesce((
                select json_agg(
                    json_build_object('kind', am.kind, 'ts', epoch_seconds(am.ts))
                    order by am.ts, am.kind
                )
                from all_markers am
            ), '[]'::json),
            'markers_announcements_omitted', (
                select count(*)
                from announcements a
                where a.rank > 50
            ),
            'traffic', stats_event_traffic(v_event, v_start_day, v_end_day),
            'utm', stats_event_utm(v_event),

            'range', case
                when v_start_day is not null then json_build_object(
                    'end_day', to_char(v_end_day, 'YYYY-MM-DD'),
                    'start_day', to_char(v_start_day, 'YYYY-MM-DD')
                )
            end,
            'tickets', case when v_is_paid then stats_event_tickets(v_event) end
        )
    );
end;
$$ language plpgsql stable;
