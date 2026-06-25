-- Returns paginated attendees for a group's event using provided filters.
create or replace function search_event_attendees(p_group_id uuid, p_filters jsonb)
returns json as $$
    with
        -- Parse filters for event scope and pagination
        filters as (
            select
                (p_filters->>'event_id')::uuid as event_id,
                (p_filters->>'limit')::int as limit_value,
                (p_filters->>'offset')::int as offset_value,
                nullif(btrim(p_filters->>'ts_query'), '') as ts_query_value
        ),
        -- Prepare text search with prefix matching
        search_filter as (
            select
                ts_rewrite(
                    websearch_to_tsquery('simple', ts_query_value),
                    format('
                        select
                            to_tsquery(''simple'', lexeme),
                            to_tsquery(''simple'', lexeme || '':*'')
                        from unnest(tsvector_to_array(to_tsvector(''simple'', %L))) as lexeme
                        ', ts_query_value
                    )
                ) as ts_query
            from filters
            where ts_query_value is not null
        ),
        -- Select visible attendee and invitation rows
        base_attendees as (
            select
                ea.checked_in,
                extract(epoch from ea.created_at)::bigint as created_at,
                u.email,
                ea.manually_invited,
                ea.registration_answers,
                ea.status,
                u.user_id,
                u.username,

                extract(epoch from ea.checked_in_at)::bigint as checked_in_at,
                ep.amount_minor,
                u.company,
                ep.currency_code,
                ep.discount_code,
                ep.event_purchase_id,
                ep.ticket_title,
                u.name,
                u.photo_url,
                err.status as refund_request_status,
                u.tsdoc,
                u.title,

                (
                    ea.status in ('confirmed', 'registration-questions-pending')
                    and u.email_verified = true
                    and coalesce(u.optional_notifications_enabled, true) = true
                    and pending_ep.event_purchase_id is null
                ) as can_receive_attendee_email
            from event_attendee ea
            join event e on e.event_id = ea.event_id
            join "user" u on u.user_id = ea.user_id
            left join lateral (
                select
                    event_purchase_id,
                    amount_minor,
                    currency_code,
                    discount_code,
                    ticket_title
                from event_purchase
                where event_id = ea.event_id
                and user_id = ea.user_id
                and status in ('completed', 'refund-requested')
                order by created_at desc, event_purchase_id desc
                limit 1
            ) ep on true
            left join lateral (
                select status
                from event_refund_request
                where event_purchase_id = ep.event_purchase_id
                order by created_at desc, event_refund_request_id desc
                limit 1
            ) err on true
            left join lateral (
                select event_purchase_id
                from event_purchase
                where event_id = ea.event_id
                and user_id = ea.user_id
                and status = 'pending'
                and hold_expires_at > current_timestamp
                order by created_at desc, event_purchase_id desc
                limit 1
            ) pending_ep on true
            where e.group_id = p_group_id
            and ea.event_id = (select event_id from filters)
            and ea.status in (
                'confirmed',
                'invitation-pending',
                'invitation-rejected',
                'registration-questions-pending'
            )
        ),
        -- Apply table filters while retaining internal search data
        filtered_attendees as (
            select *
            from base_attendees
            where (
                not exists (select 1 from search_filter)
                or exists (
                    select 1
                    from search_filter
                    where search_filter.ts_query @@ base_attendees.tsdoc
                )
            )
        ),
        -- Apply pagination and project public attendee fields
        attendees as (
            select
                checked_in,
                created_at,
                email,
                manually_invited,
                registration_answers,
                status,
                user_id,
                username,

                amount_minor,
                checked_in_at,
                company,
                currency_code,
                discount_code,
                event_purchase_id,
                name,
                photo_url,
                refund_request_status,
                ticket_title,
                title,

                can_receive_attendee_email
            from filtered_attendees
            order by coalesce(lower(name), lower(username)) asc, user_id asc
            offset (select offset_value from filters)
            limit (select limit_value from filters)
        ),
        -- Count filtered rows and event-wide eligible notification recipients
        totals as (
            select
                (
                    select count(*)::int
                    from base_attendees
                    where can_receive_attendee_email = true
                ) as all_attendees_email_recipient_total,
                count(*)::int as total
            from filtered_attendees
        ),
        -- Render attendees as JSON
        attendees_json as (
            select coalesce(json_agg(row_to_json(attendees)), '[]'::json) as attendees
            from attendees
        )
    -- Build final payload
    select json_build_object(
        'all_attendees_email_recipient_total', totals.all_attendees_email_recipient_total,
        'attendees', attendees_json.attendees,
        'total', totals.total
    )
    from attendees_json, totals;
$$ language sql;
