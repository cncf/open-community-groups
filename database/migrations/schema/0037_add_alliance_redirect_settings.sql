-- Add optional redirect settings for alliances.
create table alliance_redirect_settings (
    alliance_id uuid primary key references alliance on delete cascade,

    base_legacy_url text constraint alliance_redirect_settings_base_legacy_url_chk check (
        base_legacy_url is null
        or base_legacy_url ~ '^https?://[^[:space:]/?#]+/?$'
    )
);
