-- Returns paginated waitlist entries and waitlist offer history for an event.
create or replace function search_event_waitlist(p_group_id uuid, p_event_id uuid, p_filters jsonb)
returns json as $$
    with
        -- Parse filters for pagination
        filters as (
            select
                f.limit_value,
                f.offset_value,
                case
                    when f.sort in (
                        'created-at-asc',
                        'created-at-desc',
                        'name-asc',
                        'name-desc'
                    ) then f.sort
                    else 'created-at-asc'
                end as sort_value,
                case
                    when lower(p_filters->>'title') in ('missing', 'present')
                        then lower(p_filters->>'title')
                    else null
                end as title_value,
                f.tsquery
            from parse_search_filters(p_filters) f
        ),
        -- Combine queued users with offer history promoted from those queues
        enrollment_entries as (
            select
                null::uuid as admission_offer_id,
                null::text as admission_offer_status,
                ew.created_at,
                ew.event_id,
                ew.event_ticket_type_id,
                null::bigint as offer_expires_at,
                ew.user_id,
                row_number() over (
                    partition by ew.event_ticket_type_id
                    order by ew.created_at asc, ew.user_id asc
                )::int as waitlist_position
            from event_waitlist ew
            where ew.event_id = p_event_id

            union all

            select
                ao.admission_offer_id,
                ao.status,
                ao.created_at,
                ao.event_id,
                ao.event_ticket_type_id,
                epoch_seconds(ao.expires_at),
                ao.user_id,
                null::int
            from admission_offer ao
            where ao.event_id = p_event_id
            and ao.source = 'waitlist'
        ),
        -- Select waitlist entries with ticket and internal search data
        base_waitlist as (
            select
                ee.admission_offer_id,
                ee.admission_offer_status,
                epoch_seconds(ee.created_at) as created_at,
                ee.created_at as created_at_sort,
                ee.event_ticket_type_id,
                ee.offer_expires_at,
                ett.title as ticket_title,
                u.user_id,
                u.username,
                ee.waitlist_position,

                u.bio,
                u.bluesky_url,
                u.company,
                u.facebook_url,
                u.github_url,
                u.linkedin_url,
                u.name,
                u.photo_url,
                get_public_user_provider(u.provider) as provider,
                u.twitter_url,
                u.tsdoc,
                u.title,
                u.website_url
            from enrollment_entries ee
            join event e on e.event_id = ee.event_id
            join "user" u on u.user_id = ee.user_id
            join event_ticket_type ett
                on ett.event_ticket_type_id = ee.event_ticket_type_id
            where e.group_id = p_group_id
        ),
        -- Apply table filters while retaining internal search data
        filtered_waitlist as (
            select base_waitlist.*
            from base_waitlist
            cross join filters f
            where (
                f.tsquery is null
                or f.tsquery @@ base_waitlist.tsdoc
            )
            and (
                f.title_value is null
                or (f.title_value = 'present' and title is not null)
                or (f.title_value = 'missing' and title is null)
            )
        ),
        -- Apply pagination and project organizer waitlist fields
        waitlist as (
            select
                admission_offer_id,
                admission_offer_status,
                created_at,
                event_ticket_type_id,
                offer_expires_at,
                ticket_title,
                json_strip_nulls(json_build_object(
                    'user_id', user_id,
                    'username', username,

                    'bio', bio,
                    'bluesky_url', bluesky_url,
                    'company', company,
                    'facebook_url', facebook_url,
                    'github_url', github_url,
                    'linkedin_url', linkedin_url,
                    'name', name,
                    'photo_url', photo_url,
                    'provider', provider,
                    'title', title,
                    'twitter_url', twitter_url,
                    'website_url', website_url
                )) as "user",
                waitlist_position
            from filtered_waitlist
            cross join filters f
            order by
                case when f.sort_value = 'name-asc'
                    then coalesce(lower(name), lower(username))
                end asc nulls last,
                case when f.sort_value = 'name-desc'
                    then coalesce(lower(name), lower(username))
                end desc nulls last,
                case when f.sort_value = 'created-at-asc'
                    then created_at_sort
                end asc nulls last,
                case when f.sort_value = 'created-at-desc'
                    then created_at_sort
                end desc nulls last,
                user_id asc
            offset (select offset_value from filters)
            limit (select limit_value from filters)
        ),
        -- Count filtered waitlist entries before pagination
        totals as (
            select count(*)::int as total
            from filtered_waitlist
        ),
        -- Render waitlist entries as JSON
        waitlist_json as (
            select coalesce(
                json_agg(
                    json_build_object(
                        'created_at', created_at,
                        'event_ticket_type_id', event_ticket_type_id,
                        'ticket_title', ticket_title,
                        'user', "user",
                        'waitlist_position', waitlist_position
                    )::jsonb
                    || jsonb_strip_nulls(jsonb_build_object(
                        'admission_offer_id', admission_offer_id,
                        'admission_offer_status', admission_offer_status,
                        'offer_expires_at', offer_expires_at
                    ))
                ),
                '[]'::json
            ) as waitlist
            from waitlist
        )
    -- Build final payload
    select json_build_object(
        'total', totals.total,
        'waitlist', waitlist_json.waitlist
    )
    from waitlist_json, totals;
$$ language sql;
