-- enqueue_notification inserts notifications, templates, and attachments.
create or replace function enqueue_notification(
    p_kind text,
    p_template_data jsonb,
    p_attachments jsonb,
    p_recipients uuid[]
)
returns void as $$
declare
    v_attachment jsonb;
    v_attachment_id uuid;
    v_data bytea;
    v_notification_ids uuid[];
    v_notification_template_data_id uuid;
    v_template_hash text;
begin
    -- Insert or reuse template data and get its ID
    if p_template_data is not null then
        v_template_hash := encode(digest(convert_to(p_template_data::text, 'utf8'), 'sha256'), 'hex');

        insert into notification_template_data (data, hash)
        values (p_template_data, v_template_hash)
        on conflict (hash) do update set hash = notification_template_data.hash
        returning notification_template_data_id into v_notification_template_data_id;
    end if;

    -- Insert one notification per recipient and collect IDs
    with inserted as (
        insert into notification (kind, notification_template_data_id, user_id)
        select p_kind, v_notification_template_data_id, unnest(p_recipients)
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
        insert into attachment (content_type, data, file_name, hash)
        values (
            v_attachment->>'content_type',
            v_data,
            v_attachment->>'file_name',
            encode(digest(v_data, 'sha256'), 'hex')
        )
        on conflict (hash) do update set hash = attachment.hash
        returning attachment_id into v_attachment_id;

        -- Link the attachment to all notifications
        insert into notification_attachment (notification_id, attachment_id)
        select unnest(v_notification_ids), v_attachment_id;
    end loop;
end;
$$ language plpgsql;
