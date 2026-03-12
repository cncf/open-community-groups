-- Add expression indexes to speed up normalized redirect lookups by legacy path.

create index event_legacy_path_idx
    on event ((coalesce(
        nullif(
            trim(
                trailing '/'
                from regexp_replace(split_part(legacy_url, '?', 1), '^https?://[^/]+', '')
            ),
            ''
        ),
        '/'
    )))
    where legacy_url is not null;

create index group_legacy_path_idx
    on "group" ((coalesce(
        nullif(
            trim(
                trailing '/'
                from regexp_replace(split_part(legacy_url, '?', 1), '^https?://[^/]+', '')
            ),
            ''
        ),
        '/'
    )))
    where legacy_url is not null;
