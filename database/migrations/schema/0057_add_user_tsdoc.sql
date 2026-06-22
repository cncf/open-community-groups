-- Adds an indexed search document for user profile lookup.

alter table "user" add column tsdoc tsvector not null
    generated always as (
        setweight(to_tsvector('simple', coalesce(name, '')), 'A') ||
        setweight(to_tsvector('simple', username), 'A') ||
        setweight(to_tsvector('simple', email), 'B') ||
        setweight(to_tsvector('simple', coalesce(company, '')), 'C') ||
        setweight(to_tsvector('simple', coalesce(title, '')), 'C')
    ) stored;

create index user_tsdoc_idx on "user" using gin (tsdoc);
