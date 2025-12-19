-- Notification template data table for deduplicating template data across notifications.
-- Uses hash-based deduplication similar to the attachment table pattern.
create table notification_template_data (
    notification_template_data_id uuid primary key default gen_random_uuid(),
    created_at timestamptz default current_timestamp not null,
    data jsonb not null,
    hash text not null constraint notification_template_data_hash_idx unique
);

-- Add FK to notification table and drop old column.
alter table notification
    add column notification_template_data_id uuid references notification_template_data;
alter table notification
    drop column template_data;
