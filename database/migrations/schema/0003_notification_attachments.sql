-- Stores files that can be referenced by multiple notifications.
create table attachment (
    attachment_id uuid primary key default gen_random_uuid(),
    content_type text not null check (content_type <> ''),
    created_at timestamptz default current_timestamp not null,
    data bytea not null,
    file_name text not null,
    hash text not null constraint attachment_hash_idx unique
);

-- Junction table to link notifications to their attachments.
create table notification_attachment (
    notification_id uuid not null references notification(notification_id) on delete cascade,
    attachment_id uuid not null references attachment(attachment_id) on delete restrict,
    primary key (notification_id, attachment_id)
);

create index notification_attachment_attachment_id_idx on notification_attachment (attachment_id);
