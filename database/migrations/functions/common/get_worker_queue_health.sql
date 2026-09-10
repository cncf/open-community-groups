-- Returns backlog signals for the badge award, notification and payment job queues.
create or replace function get_worker_queue_health()
returns json as $$
    with
        -- Summarize the durable badge award job queue
        badge_award_jobs as (
            select
                count(*) filter (where baj.status = 'pending')::bigint as pending,
                count(*) filter (where baj.status = 'processing')::bigint as processing,
                floor(extract(
                    epoch from current_timestamp - min(baj.created_at) filter (where baj.status = 'pending')
                ))::bigint as oldest_pending_age_secs
            from badge_award_job baj
            where baj.status in ('pending', 'processing')
        ),
        -- Summarize the notification delivery queue
        notifications as (
            select
                count(*) filter (where n.delivery_status = 'pending')::bigint as pending,
                count(*) filter (where n.delivery_status = 'processing')::bigint as processing,
                floor(extract(
                    epoch from current_timestamp - min(n.created_at) filter (where n.delivery_status = 'pending')
                ))::bigint as oldest_pending_age_secs
            from notification n
            where n.delivery_status in ('pending', 'processing')
        ),
        -- Summarize the durable payment job queue
        payment_jobs as (
            select
                count(*) filter (where pj.status = 'pending')::bigint as pending,
                count(*) filter (where pj.status = 'processing')::bigint as processing,
                floor(extract(
                    epoch from current_timestamp - min(pj.created_at) filter (where pj.status = 'pending')
                ))::bigint as oldest_pending_age_secs
            from payment_job pj
            where pj.status in ('pending', 'processing')
        )
    -- Build the health payload
    select json_build_object(
        'badge_award_jobs', (
            select json_build_object(
                'pending', pending,
                'processing', processing,
                'oldest_pending_age_secs', oldest_pending_age_secs
            )
            from badge_award_jobs
        ),
        'notifications', (
            select json_build_object(
                'pending', pending,
                'processing', processing,
                'oldest_pending_age_secs', oldest_pending_age_secs
            )
            from notifications
        ),
        'payment_jobs', (
            select json_build_object(
                'pending', pending,
                'processing', processing,
                'oldest_pending_age_secs', oldest_pending_age_secs
            )
            from payment_jobs
        )
    );
$$ language sql stable;
