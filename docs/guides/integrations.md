<!-- markdownlint-disable MD013 -->

# Integration Contributor Guide

Use this guide when adding a third-party provider, partner service, or external content source to GOUP.

## Code Location

Put provider-specific clients and normalized types in `ocg-server/src/integrations/`. Add a module export in
`ocg-server/src/integrations.rs`; keep HTTP request details, response decoding, and provider validation there.

Keep handlers focused on authorization and HTTP responses. Put recurring work in `ocg-server/src/services/` and
start it from `ocg-server/src/main.rs`.

## Configuration and Secrets

1. Add an optional, typed configuration block in `ocg-server/src/config.rs`.
2. Validate enabled integrations at startup, including valid URLs, scheduling values, and required credentials.
3. Add only non-secret example values to `.config/ocg/server.yml`.
4. Load secrets from `OCG_` environment variables, such as
   `OCG_INTEGRATIONS__PROVIDER__API_KEY`.
5. Never commit API keys, tokens, webhook secrets, or customer URLs that are not intended to be public.

The local server configuration is ignored by Git so developers can safely set their own credentials.

## Data and Permissions

When an integration persists data:

1. Create a schema migration under `database/migrations/schema/`.
2. Add SQL functions under `database/migrations/functions/` and register them in
   `database/migrations/functions/001_load_functions.sql`.
3. Extend the appropriate database trait and its mock in `ocg-server/src/db/`.
4. Enforce the existing alliance or group permission in the handler before mutating data.
5. Record source URLs, external identifiers, run status, and deduplication keys so retries are safe.

Do not let a background worker bypass authorization. Store the authorized actor that configured the integration and
reuse existing domain flows for side effects such as event publication and notifications.

## User Experience

- Add group-scoped controls to the Group Dashboard and alliance-scoped controls to the Alliance Dashboard.
- Surface last-run status and actionable failures without exposing provider secrets.
- Put public partner attribution on the relevant alliance page only when the partner is marked public.
- Reuse Askama templates and HTMX routes instead of embedding provider logic in browser code.

## HTTP and Worker Safety

- Use explicit request timeouts, bounded retries, and structured error logs.
- Validate user-entered URLs before storing them.
- Treat fetched data as untrusted; require the fields needed by the target GOUP entity.
- Deduplicate provider records before creating entities.
- Make scheduled and manual runs idempotent.
- Keep webhooks authenticated and verify provider signatures when the provider supports them.

## Tests and Review

At minimum, cover configuration validation, provider response parsing, permission checks, deduplication, and failure
handling. Run:

```bash
cargo fmt --all -- --check
cargo check -p ocg-server
cargo test -p ocg-server
```

For migrations or dashboard changes, also run the relevant database and browser checks described in the
[Project Contributors Runbook](project-contributors-runbook.md).
