-- Add optional redirect settings for communities.
create table community_redirect_settings (
    community_id uuid primary key references community on delete cascade,

    base_legacy_url text constraint community_redirect_settings_base_legacy_url_chk check (
        base_legacy_url is null
        or base_legacy_url ~ '^https?://[^[:space:]/?#]+/?$'
    )
);
