-- Add the group inbox for users contacting groups.

-- Catalog of inbox conversation states.
create table inbox_conversation_status (
    inbox_conversation_status_id text primary key,
    display_name text not null unique check (btrim(display_name) <> '')
);

-- Seed the supported inbox conversation states.
insert into inbox_conversation_status (inbox_conversation_status_id, display_name) values
    ('answered', 'Answered'),
    ('closed', 'Closed'),
    ('open', 'Open'),
    ('spam', 'Spam');

-- Conversations between one user and one group.
create table inbox_conversation (
    inbox_conversation_id uuid primary key default gen_random_uuid(),
    created_at timestamptz default current_timestamp not null,
    group_id uuid not null references "group",
    inbox_conversation_status_id text not null default 'open' references inbox_conversation_status,
    last_message_at timestamptz default current_timestamp not null,

    event_id uuid,
    user_id uuid references "user" on delete set null,

    constraint inbox_conversation_event_id_group_id_fkey foreign key (event_id, group_id)
        references event (event_id, group_id) on delete set null (event_id)
);

-- Plain-text messages in a conversation.
create table inbox_message (
    inbox_message_id uuid primary key default gen_random_uuid(),
    body text not null,
    created_at timestamptz default current_timestamp not null,
    inbox_conversation_id uuid not null references inbox_conversation,
    kind text not null,

    author_user_id uuid references "user" on delete set null,

    constraint inbox_message_body_chk check (body ~ '\S' and char_length(body) <= 5000),
    constraint inbox_message_kind_chk check (
        kind = any(array['group-reply', 'initial', 'user-reply']::text[])
    )
);

-- Support conversation lookups by event, group, status and user, and message
-- lookups by author and conversation.
create index inbox_conversation_event_id_idx on inbox_conversation (event_id);
create index inbox_conversation_group_id_last_message_at_idx on inbox_conversation (
    group_id,
    last_message_at desc
);
create index inbox_conversation_group_id_open_idx on inbox_conversation (group_id)
    where inbox_conversation_status_id = 'open';
create index inbox_conversation_user_id_created_at_idx on inbox_conversation (
    user_id,
    created_at desc
);
create index inbox_conversation_user_id_last_message_at_idx on inbox_conversation (
    user_id,
    last_message_at desc
);
create index inbox_message_author_user_id_kind_created_at_idx on inbox_message (
    author_user_id,
    kind,
    created_at desc
);
create index inbox_message_inbox_conversation_id_created_at_idx on inbox_message (
    inbox_conversation_id,
    created_at
);
create unique index inbox_message_inbox_conversation_id_initial_idx on inbox_message (
    inbox_conversation_id
) where kind = 'initial';

-- Inbox permission and role grants.
insert into group_permission (group_permission_id, display_name) values
    ('group.inbox.write', 'Inbox Write');
insert into community_role_group_permission (community_role_id, group_permission_id) values
    ('admin', 'group.inbox.write'),
    ('groups-manager', 'group.inbox.write');
insert into group_role_group_permission (group_role_id, group_permission_id) values
    ('admin', 'group.inbox.write'),
    ('events-manager', 'group.inbox.write');

-- Inbox notification kinds (direct correspondence, never optional).
insert into notification_kind (name, optional_notification) values
    ('inbox-message-received', false),
    ('inbox-reply-received', false);

-- Replace the audit helper with one that accepts the write time.
drop function if exists insert_audit_log(text, uuid, text, uuid, uuid, uuid, uuid, jsonb);
