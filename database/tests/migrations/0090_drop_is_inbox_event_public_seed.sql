-- Seeds schema-89 inbox conversations for the inbox event visibility helper drop upgrade test.

begin;

\set communityID '90000000-0000-0000-0000-000000000001'
\set eventCategoryID '90000000-0000-0000-0000-000000000002'
\set groupCategoryID '90000000-0000-0000-0000-000000000003'
\set groupID '90000000-0000-0000-0000-000000000004'
\set privateConversationID '90000000-0000-0000-0000-000000000005'
\set publicConversationID '90000000-0000-0000-0000-000000000006'
\set publicEventID '90000000-0000-0000-0000-000000000007'
\set publicTicketTypeID '90000000-0000-0000-0000-000000000010'
\set unpublishedEventID '90000000-0000-0000-0000-000000000008'
\set unpublishedTicketTypeID '90000000-0000-0000-0000-000000000011'
\set userID '90000000-0000-0000-0000-000000000009'

-- Community hosting the migration fixtures
insert into community (
    community_id,
    banner_mobile_url,
    banner_url,
    description,
    display_name,
    logo_url,
    name
) values (
    :'communityID',
    'https://example.test/banner-mobile.png',
    'https://example.test/banner.png',
    'Inbox visibility upgrade fixtures',
    'Inbox Visibility Community',
    'https://example.test/logo.png',
    'inbox-visibility-community'
);

-- Event category of the linked events
insert into event_category (community_id, event_category_id, name)
values (:'communityID', :'eventCategoryID', 'Inbox visibility events');

-- Group category of the fixture group
insert into group_category (community_id, group_category_id, name)
values (:'communityID', :'groupCategoryID', 'Inbox visibility groups');

-- User who started both conversations
insert into "user" (auth_hash, email, email_verified, user_id, username)
values ('hash', 'inbox-visibility-user@example.test', true, :'userID', 'inbox-visibility-user');

-- Active group owning the linked events
insert into "group" (community_id, group_category_id, group_id, name, slug)
values (:'communityID', :'groupCategoryID', :'groupID', 'Inbox Visibility Group', 'inbox-visibility-group');

-- Published event whose page is public
insert into event (
    description,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    published,
    slug,
    starts_at,
    timezone
) values (
    'Public inbox event',
    :'eventCategoryID',
    :'publicEventID',
    'virtual',
    :'groupID',
    'Public Inbox Event',
    true,
    'public-inbox-event',
    '2099-01-01 09:00:00+00',
    'UTC'
);

-- Unpublished event whose page is not public
insert into event (
    description,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    slug,
    starts_at,
    timezone
) values (
    'Unpublished inbox event',
    :'eventCategoryID',
    :'unpublishedEventID',
    'virtual',
    :'groupID',
    'Unpublished Inbox Event',
    'unpublished-inbox-event',
    '2099-02-01 09:00:00+00',
    'UTC'
);

-- Ticket tier required by the public event
insert into event_ticket_type (availability, event_id, event_ticket_type_id, "order", seats_total, title)
values ('public', :'publicEventID', :'publicTicketTypeID', 1, 20, 'General admission');

-- Ticket tier required by the unpublished event
insert into event_ticket_type (availability, event_id, event_ticket_type_id, "order", seats_total, title)
values ('public', :'unpublishedEventID', :'unpublishedTicketTypeID', 1, 20, 'General admission');

-- Conversation linked to the public event
insert into inbox_conversation (event_id, group_id, inbox_conversation_id, user_id)
values (:'publicEventID', :'groupID', :'publicConversationID', :'userID');

-- Conversation linked to the unpublished event
insert into inbox_conversation (event_id, group_id, inbox_conversation_id, user_id)
values (:'unpublishedEventID', :'groupID', :'privateConversationID', :'userID');

-- Message starting the public event conversation
insert into inbox_message (author_user_id, body, inbox_conversation_id, kind)
values (:'userID', 'Is there a recording?', :'publicConversationID', 'initial');

-- Message starting the unpublished event conversation
insert into inbox_message (author_user_id, body, inbox_conversation_id, kind)
values (:'userID', 'When will it be announced?', :'privateConversationID', 'initial');

commit;
