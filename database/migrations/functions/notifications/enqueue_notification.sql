-- enqueue_notification inserts notifications, templates, and attachments and
-- returns the identifiers of the notifications created. Recipient preferences
-- (category opt-outs and group mutes) are applied here, when the notification
-- is queued, and nothing is written when no recipient remains; group-mutable
-- kinds must name the groups the notification is about.
create or replace function enqueue_notification(
    p_kind text,
    p_template_data jsonb,
    p_attachments jsonb,
    p_recipients uuid[],
    p_group_ids uuid[] default null
)
returns uuid[] as $$
declare
    v_attachment jsonb;
    v_attachment_hash text;
    v_attachment_id uuid;
    v_data bytea;
    v_group_mutable boolean;
    v_notification_ids uuid[];
    v_notification_template_data_id uuid;
    v_recipients uuid[];
    v_template_hash text;
begin
    -- Resolve notification kind metadata before creating notification data
    select nc.group_mutable
    into v_group_mutable
    from notification_kind nk
    left join notification_category nc using (notification_category_id)
    where nk.name = p_kind;

    -- Reject unknown notification kinds
    if not found then
        raise exception 'notification kind does not exist: %', p_kind
            using errcode = 'foreign_key_violation';
    end if;

    -- Require a complete group scope for group-mutable kinds
    if coalesce(v_group_mutable, false)
       and (
           p_group_ids is null
           or cardinality(p_group_ids) = 0
           or array_position(p_group_ids, null) is not null
       ) then
        raise exception 'group ids are required for notification kind: %', p_kind;
    end if;

    -- Keep only recipients who accept this kind
    select coalesce(array_agg(a.user_id order by a.ordinal), '{}')
    into v_recipients
    from users_accepting_notification(p_kind, p_recipients, p_group_ids) a;

    -- Write nothing when no recipient remains
    if cardinality(v_recipients) = 0 then
        return '{}'::uuid[];
    end if;

    -- Insert or reuse template data and get its ID when provided
    if p_template_data is not null then
        -- Insert the template data unless its hash is already stored
        v_template_hash := encode(digest(convert_to(p_template_data::text, 'utf8'), 'sha256'), 'hex');

        insert into notification_template_data (data, hash)
        values (p_template_data, v_template_hash)
        on conflict (hash) do nothing
        returning notification_template_data_id into v_notification_template_data_id;

        -- Reuse the stored template data without writing a new row version
        if v_notification_template_data_id is null then
            select notification_template_data_id
            into v_notification_template_data_id
            from notification_template_data
            where hash = v_template_hash;

            -- Fail instead of enqueuing notifications without their template data
            if not found then
                raise exception 'notification template data not found';
            end if;
        end if;
    end if;

    -- Insert one notification per recipient and collect IDs
    with inserted as (
        insert into notification (kind, notification_template_data_id, user_id)
        select p_kind, v_notification_template_data_id, unnest(v_recipients)
        returning notification_id
    )
    select coalesce(array_agg(notification_id order by notification_id), '{}')
    into v_notification_ids
    from inserted;

    -- Insert or reuse attachments and link each to all notifications
    for v_attachment in
        select value
        from jsonb_array_elements(p_attachments)
    loop
        -- Insert attachment and get its ID, using hash to avoid duplicates
        v_data := decode(v_attachment->>'data_base64', 'base64');
        v_attachment_hash := encode(digest(v_data, 'sha256'), 'hex');
        insert into attachment (content_type, data, file_name, hash)
        values (
            v_attachment->>'content_type',
            v_data,
            v_attachment->>'file_name',
            v_attachment_hash
        )
        on conflict (hash) do nothing
        returning attachment_id into v_attachment_id;

        -- Reuse the stored attachment without writing a new row version
        if v_attachment_id is null then
            select attachment_id
            into v_attachment_id
            from attachment
            where hash = v_attachment_hash;

            -- Fail instead of linking notifications to a missing attachment
            if not found then
                raise exception 'notification attachment not found';
            end if;
        end if;

        -- Link the attachment to all notifications
        insert into notification_attachment (notification_id, attachment_id)
        select unnest(v_notification_ids), v_attachment_id;
    end loop;

    -- Return the identifiers so callers can correlate enqueue and delivery
    return v_notification_ids;
end;
$$ language plpgsql;
