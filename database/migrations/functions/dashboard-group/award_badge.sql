-- Awards a badge atomically to an explicit eligible recipient list.
create or replace function award_badge(
    p_actor_user_id uuid,
    p_community_id uuid,
    p_group_id uuid,
    p_badge_id uuid,
    p_user_ids uuid[],
    p_event_id uuid
)
returns json as $$
declare
    v_awarded_count integer := 0;
    v_badge badge%rowtype;
    v_badge_status_list_id uuid;
    v_community_name text;
    v_display_order integer;
    v_eligible_recipient_ids uuid[];
    v_group_name text;
    v_index_attempts integer;
    v_notification_recipient_ids uuid[] := '{}';
    v_recipient_user_id uuid;
    v_recipient_user_ids uuid[];
    v_skipped_count integer := 0;
    v_snapshot jsonb;
    v_status_list_index integer;
    v_theme jsonb;
    v_user_badge_id uuid;
begin
    -- Serialize group status-list allocation and authorize the requested boundary
    select g.name, c.display_name
    into v_group_name, v_community_name
    from "group" g
    join community c using (community_id)
    where g.community_id = p_community_id
    and g.group_id = p_group_id
    and g.deleted = false
    for update of g;

    if not found then
        raise exception 'group not found';
    end if;
    if not user_has_group_permission(
        p_community_id,
        p_group_id,
        p_actor_user_id,
        'group.events.write'
    ) then
        raise exception 'badge permission denied' using errcode = 'insufficient_privilege';
    end if;

    -- Lock the definition used to build every immutable issuance snapshot
    select *
    into v_badge
    from badge
    where badge_id = p_badge_id
    and group_id = p_group_id
    for share;

    if not found then
        raise exception 'badge not found';
    end if;

    -- Normalize duplicates before validating the complete requested set
    if p_user_ids is null
       or cardinality(p_user_ids) = 0
       or array_position(p_user_ids, null) is not null then
        raise exception 'badge recipients cannot be empty';
    end if;
    select array_agg(distinct recipients.user_id order by recipients.user_id)
    into v_recipient_user_ids
    from unnest(p_user_ids) as recipients(user_id);

    if p_event_id is not null then
        -- Lock the active event that defines contributor and attendee eligibility
        perform 1
        from event
        where event_id = p_event_id
        and group_id = p_group_id
        and canceled = false
        and deleted = false
        for share;

        if not found then
            raise exception 'event not found';
        end if;

        -- Validate every recipient as a verified event participant
        select coalesce(array_agg(u.user_id order by u.user_id), '{}'::uuid[])
        into v_eligible_recipient_ids
        from "user" u
        where u.email_verified = true
        and u.user_id = any(v_recipient_user_ids)
        and (
            exists (
                select 1
                from event_attendee ea
                where ea.event_id = p_event_id
                and ea.status = 'confirmed'
                and ea.user_id = u.user_id
            )
            or exists (
                select 1
                from event_host eh
                where eh.event_id = p_event_id
                and eh.user_id = u.user_id
            )
            or exists (
                select 1
                from event_speaker es
                where es.event_id = p_event_id
                and es.user_id = u.user_id
            )
            or exists (
                select 1
                from session_speaker ss
                join session s using (session_id)
                where s.event_id = p_event_id
                and ss.user_id = u.user_id
            )
        );
    else
        -- Validate every recipient as a verified accepted group team member
        select coalesce(array_agg(u.user_id order by u.user_id), '{}'::uuid[])
        into v_eligible_recipient_ids
        from group_team gt
        join "user" u using (user_id)
        where gt.accepted = true
        and gt.group_id = p_group_id
        and u.email_verified = true
        and u.user_id = any(v_recipient_user_ids);
    end if;

    if cardinality(v_eligible_recipient_ids) <> cardinality(v_recipient_user_ids) then
        raise exception 'badge recipient is not eligible';
    end if;

    -- Serialize recipient badge order and duplicate checks in canonical order
    perform 1
    from "user" u
    where u.user_id = any(v_recipient_user_ids)
    order by u.user_id
    for update;

    -- Build one immutable snapshot from the locked definition and issuer state
    v_snapshot := jsonb_build_object(
        'criteria', v_badge.criteria,
        'description', v_badge.description,
        'image_file_name', v_badge.image_file_name,
        'issuer', jsonb_build_object(
            'community_id', p_community_id,
            'community_name', v_community_name,
            'group_id', p_group_id,
            'group_name', v_group_name
        ),
        'name', v_badge.name
    );
    select theme into v_theme from site limit 1;

    -- Insert one credential per recipient while skipping active holders
    foreach v_recipient_user_id in array v_recipient_user_ids
    loop
        if exists (
            select 1
            from user_badge
            where badge_id = p_badge_id
            and revoked_at is null
            and user_id = v_recipient_user_id
        ) then
            v_skipped_count := v_skipped_count + 1;
            continue;
        end if;

        -- Select or create a group-scoped status list with remaining capacity
        select bsl.badge_status_list_id
        into v_badge_status_list_id
        from badge_status_list bsl
        where bsl.group_id = p_group_id
        and (
            select count(*)
            from user_badge ub
            where ub.badge_status_list_id = bsl.badge_status_list_id
        ) < 131072
        order by bsl.created_at desc, bsl.badge_status_list_id desc
        limit 1
        for update;

        if not found then
            insert into badge_status_list (group_id)
            values (p_group_id)
            returning badge_status_list_id into v_badge_status_list_id;
        end if;

        -- Allocate a random unused status index with a deterministic fallback
        v_index_attempts := 0;
        loop
            v_status_list_index := floor(random() * 131072)::integer;
            exit when not exists (
                select 1
                from user_badge
                where badge_status_list_id = v_badge_status_list_id
                and status_list_index = v_status_list_index
            );

            v_index_attempts := v_index_attempts + 1;
            if v_index_attempts >= 128 then
                select candidate
                into v_status_list_index
                from generate_series(0, 131071) candidate
                where not exists (
                    select 1
                    from user_badge
                    where badge_status_list_id = v_badge_status_list_id
                    and status_list_index = candidate
                )
                order by candidate
                limit 1;
                exit;
            end if;
        end loop;

        -- Append the award to the recipient's active display order
        select coalesce(max(display_order) + 1, 0)
        into v_display_order
        from user_badge
        where revoked_at is null
        and user_id = v_recipient_user_id;

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
            v_badge_status_list_id,
            v_display_order,
            p_group_id,
            v_snapshot,
            v_status_list_index,

            p_badge_id,
            p_event_id,
            v_recipient_user_id
        )
        returning user_badge_id into v_user_badge_id;

        v_awarded_count := v_awarded_count + 1;
        v_notification_recipient_ids := array_append(
            v_notification_recipient_ids,
            v_recipient_user_id
        );

        -- Record each durable credential issuance after its insert succeeds
        perform insert_audit_log(
            'badge_awarded',
            p_actor_user_id,
            'user_badge',
            v_user_badge_id,
            p_community_id,
            p_group_id,
            p_event_id,
            jsonb_build_object('badge_name', v_badge.name)
        );
    end loop;

    -- Enqueue only newly inserted awards in the same database operation
    if v_awarded_count > 0 then
        perform enqueue_notification(
            'badge-awarded',
            jsonb_build_object(
                'badge', v_snapshot,
                'dashboard_url', '/dashboard/user?tab=badges',
                'theme', v_theme
            ),
            '[]'::jsonb,
            v_notification_recipient_ids
        );
    end if;

    -- Return stable counts for organizer feedback
    return json_build_object(
        'awarded_count', v_awarded_count,
        'skipped_count', v_skipped_count
    );
end;
$$ language plpgsql;
