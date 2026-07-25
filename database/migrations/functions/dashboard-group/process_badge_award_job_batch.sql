-- Processes one rate-limited batch from a claimed badge award job.
create or replace function process_badge_award_job_batch(
    p_badge_award_job_id uuid,
    p_claim_id uuid,
    p_batch_size integer default 25,
    p_rate_limit integer default 500
)
returns jsonb as $$
declare
    v_allowed_count integer;
    v_awarded_count integer := 0;
    v_awarded_last_minute integer;
    v_batch_recipient_ids uuid[];
    v_display_order integer;
    v_is_complete boolean;
    v_job badge_award_job%rowtype;
    v_next_recipient_offset integer;
    v_notification_recipient_ids uuid[] := '{}';
    v_recipient_user_id uuid;
    v_remaining_count integer;
    v_skipped_count integer := 0;
    v_status_list badge_status_list%rowtype;
    v_status_list_index integer;
    v_theme jsonb;
    v_user_badge_id uuid;
begin
    -- Validate worker-controlled processing limits
    if p_batch_size <= 0 then
        raise exception 'badge award batch size must be positive';
    end if;
    if p_rate_limit <= 0 then
        raise exception 'badge award rate limit must be positive';
    end if;

    -- Serialize issuance admission across every application replica
    perform pg_advisory_xact_lock(hashtextextended('ocg:badge-award-issuance', 0));

    -- Lock and validate the expected processing claim
    select baj.*
    into v_job
    from badge_award_job baj
    where baj.badge_award_job_id = p_badge_award_job_id
    and baj.claim_id = p_claim_id
    and baj.status = 'processing'
    for update;

    if not found then
        raise exception 'badge award job claim not found';
    end if;

    -- Bound this batch by remaining work and the rolling issuance budget
    select count(*)::integer
    into v_awarded_last_minute
    from user_badge
    where awarded_at >= current_timestamp - interval '1 minute';

    v_remaining_count := v_job.accepted_count - v_job.next_recipient_offset;
    v_allowed_count := least(
        p_batch_size,
        greatest(0, p_rate_limit - v_awarded_last_minute),
        v_remaining_count
    );

    if v_allowed_count = 0 and v_remaining_count > 0 then
        -- Release rate-limited work without consuming its failure budget
        update badge_award_job
        set
            claim_id = null,
            claimed_at = null,
            next_attempt_at = current_timestamp + interval '5 seconds',
            status = 'pending',
            updated_at = current_timestamp
        where badge_award_job_id = p_badge_award_job_id;

        return jsonb_build_object(
            'completed', false,
            'processed_count', 0,
            'rate_limited', true
        );
    end if;

    -- Select and lock this canonical recipient slice before assigning display order
    if v_allowed_count > 0 then
        select coalesce(array_agg(recipient.user_id order by recipient.position), '{}'::uuid[])
        into v_batch_recipient_ids
        from (
            select bajr.position, bajr.user_id
            from badge_award_job_recipient bajr
            where bajr.badge_award_job_id = p_badge_award_job_id
            and bajr.position >= v_job.next_recipient_offset
            order by bajr.position
            limit v_allowed_count
        ) recipient;

        if cardinality(v_batch_recipient_ids) <> v_allowed_count then
            raise exception 'badge award job recipients are incomplete';
        end if;

        perform 1
        from "user" u
        where u.user_id = any(v_batch_recipient_ids)
        order by u.user_id
        for update;
    else
        v_batch_recipient_ids := '{}'::uuid[];
    end if;

    -- Insert issued credentials while preserving idempotent skips
    foreach v_recipient_user_id in array v_batch_recipient_ids
    loop
        if not exists (
            select 1
            from "user" u
            where u.user_id = v_recipient_user_id
        ) or exists (
            select 1
            from user_badge ub
            where ub.badge_id = v_job.badge_id
            and ub.revoked_at is null
            and ub.user_id = v_recipient_user_id
        ) then
            v_skipped_count := v_skipped_count + 1;
            continue;
        end if;

        -- Persist a filled list position before selecting another list
        if v_status_list.badge_status_list_id is not null
           and v_status_list.allocation_position >= 131072 then
            update badge_status_list
            set allocation_position = v_status_list.allocation_position
            where badge_status_list_id = v_status_list.badge_status_list_id;
            v_status_list.badge_status_list_id := null;
        end if;

        -- Lock or create the newest group list with remaining capacity
        if v_status_list.badge_status_list_id is null then
            select bsl.*
            into v_status_list
            from badge_status_list bsl
            where bsl.group_id = v_job.group_id
            and bsl.allocation_position < 131072
            order by bsl.created_at desc, bsl.badge_status_list_id desc
            limit 1
            for update;

            if not found then
                insert into badge_status_list (group_id)
                values (v_job.group_id)
                returning * into v_status_list;
            end if;
        end if;

        -- Map the reserved position through the list's collision-free permutation
        v_status_list_index := ((
            v_status_list.allocation_offset::bigint
            + v_status_list.allocation_position::bigint
                * v_status_list.allocation_stride::bigint
        ) % 131072)::integer;
        v_status_list.allocation_position := v_status_list.allocation_position + 1;

        -- Append the award to the recipient's active display order
        select coalesce(max(ub.display_order) + 1, 0)
        into v_display_order
        from user_badge ub
        where ub.revoked_at is null
        and ub.user_id = v_recipient_user_id;

        insert into user_badge (
            badge_status_list_id,
            display_order,
            group_id,
            snapshot,
            status_list_index,

            badge_id,
            event_id,
            user_id
        ) values (
            v_status_list.badge_status_list_id,
            v_display_order,
            v_job.group_id,
            v_job.badge_snapshot,
            v_status_list_index,

            v_job.badge_id,
            v_job.event_id,
            v_recipient_user_id
        )
        returning user_badge_id into v_user_badge_id;

        v_awarded_count := v_awarded_count + 1;
        v_notification_recipient_ids := array_append(
            v_notification_recipient_ids,
            v_recipient_user_id
        );

        -- Record the durable issuance using the actor snapshot retained by the job
        insert into audit_log (
            action,
            actor_user_id,
            actor_username,
            community_id,
            details,
            event_id,
            group_id,
            resource_id,
            resource_type
        ) values (
            'badge_awarded',
            v_job.actor_user_id,
            v_job.actor_username,
            v_job.community_id,
            jsonb_build_object('badge_name', v_job.badge_snapshot->>'name'),
            v_job.event_id,
            v_job.group_id,
            v_user_badge_id,
            'user_badge'
        );
    end loop;

    -- Persist the final allocation cursor used by this batch
    if v_status_list.badge_status_list_id is not null then
        update badge_status_list
        set allocation_position = v_status_list.allocation_position
        where badge_status_list_id = v_status_list.badge_status_list_id;
    end if;

    -- Queue notifications only for credentials inserted by this transaction
    if v_awarded_count > 0 then
        select theme
        into v_theme
        from site
        limit 1;

        perform enqueue_notification(
            'badge-awarded',
            jsonb_build_object(
                'badge', v_job.badge_snapshot,
                'dashboard_url', '/dashboard/user?tab=badges',
                'theme', v_theme
            ),
            '[]'::jsonb,
            v_notification_recipient_ids
        );
    end if;

    -- Advance progress and release or complete the current claim atomically
    v_next_recipient_offset := v_job.next_recipient_offset + v_allowed_count;
    v_is_complete := v_next_recipient_offset >= v_job.accepted_count;

    if v_is_complete then
        delete from badge_award_job_recipient
        where badge_award_job_id = p_badge_award_job_id;
    end if;

    update badge_award_job
    set
        awarded_count = awarded_count + v_awarded_count,
        claim_id = null,
        claimed_at = null,
        completed_at = case when v_is_complete then current_timestamp else null end,
        error = null,
        next_attempt_at = case
            when v_is_complete then next_attempt_at
            else current_timestamp + interval '1 second'
        end,
        next_recipient_offset = v_next_recipient_offset,
        skipped_count = skipped_count + v_skipped_count,
        status = case when v_is_complete then 'completed' else 'pending' end,
        updated_at = current_timestamp
    where badge_award_job_id = p_badge_award_job_id;

    return jsonb_build_object(
        'completed', v_is_complete,
        'processed_count', v_allowed_count,
        'rate_limited', false
    );
end;
$$ language plpgsql;
