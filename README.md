# GOUP Alliance

**GOUP Alliance** is a community platform for builders, founders, and open
source contributors to discover groups, join events, share opportunities, and
map the startup and open source landscape.

Live site: <https://goup.vc>

This repository powers the GOUP public site, dashboards, jobs board, landscape
directory, wiki, and remote MCP operational tools.

## What Is Live

- Public GOUP Alliance site at <https://goup.vc>
- GOUP Baku and San Francisco chapters
- Event discovery and RSVP flows
- Jobs board with saved-interest applications
- Startup and open source landscape directory
- Wiki with AI, open source, and entrepreneurship reading feeds
- Public stats page with alliance, jobs, landscape, and engagement metrics
- Dashboard tools for users, group admins, and alliance admins
- Remote MCP server at `/mcp` for operational and content-management tools

## Features

### Discovery

- Browse alliances, groups, and events from a public site
- Explore events in list or calendar views
- Explore groups in list or map views
- Search and filter by alliance, category, region, date, event type, jobs, and
  landscape entries
- View platform stats for active members, upcoming events, jobs, saved interest,
  landscape entries, attendee averages, and engagement signals

### Alliances and Groups

- Alliance dashboards for branding, taxonomy, teams, analytics, and groups
- Dedicated site for each alliance
- Dedicated site for each group
- Group dashboards for settings, events, members, sponsors, analytics, and teams
- Member management and group-wide communication
- Multi-alliance support from a single deployment
- Role-based alliance and group access with audit logs
- Shared regions and categories for organizing groups and events
- Sponsor profiles that can be reused across group and event pages

### Events

- Call for Speakers workflows with reusable proposals, co-speaker invitations,
  reviewer feedback, ratings, and accepted sessions
- Capacity management with sold-out, waitlist, and invitation-review options
- Custom event pages with banners, galleries, tags, markdown descriptions, and
  social sharing
- Host in-person, virtual, or hybrid events
- Multi-session agendas with per-session timing and speakers
- Paid ticketing with Stripe Checkout, ticket tiers, discount codes, and refund
  review
- Recurring event creation with series-aware publish, unpublish, cancel, and
  delete actions
- RSVP, attendance tracking, QR code check-in, and manual organizer check-in
- Manual LinkedIn and Instagram sharing helpers for event promotion

### Meetings

- Zoom and Google Meet integration with automatic meeting setup
- Per-event and per-session meeting support with automatic meeting cleanup
- Support for manual meeting and recording links, plus organizer-controlled
  recording visibility

### Jobs

- Public job board for alliance members and companies
- Dashboard for posting, publishing, unpublishing, and deleting jobs
- Saved-interest applications with applicant details for job posters
- Automatic 30-day job expiry with republish support

### Landscape and Wiki

- Public landscape directory for startups and open source projects
- Alliance-admin management for landscape entries
- Search and filtering by kind, category, tags, and alliance
- Wiki page with curated RSS/Atom sources for AI, open source, and
  entrepreneurship

### Notifications

- Automated notifications for registrations, reminders, event changes,
  cancellations, waitlists, speaker submissions, and refunds
- Calendar attachments for event confirmations and updates
- Custom emails to event attendees and group members, with user preferences for
  optional notifications

### Users

- LinkedIn-focused login for GOUP members, with support for email and GitHub
  login in the underlying platform
- LinkedIn blocklist support for removed accounts
- Invitation inbox for alliance and group team access
- Personal dashboard for upcoming events, profile, invitations, proposals,
  submissions, jobs, and audit history
- User profiles with photos, social links, interests, and location

### Remote MCP

- HTTP JSON-RPC MCP server for GOUP operational tools
- Bearer-token authentication and mutation guard
- Tools for listing/searching groups, events, members, teams, jobs, wiki, and
  landscape entries
- Tools for creating and updating draft events and submitting talks when
  mutations are enabled

## Development

This repository contains a Rust web server, PostgreSQL schema/functions,
Askama templates, Tailwind CSS, browser-side JavaScript, and Playwright tests.
The app is developed from the repository root unless a command says otherwise.

### Prerequisites

Install these tools before running the app locally:

- Rust `1.95.0` or newer, preferably through `rustup`.
- PostgreSQL with PostGIS available. PostgreSQL 15, 16, or 17 works for local
  development.
- `psql`, `createdb`, and `dropdb` on your `PATH`.
- `tern` for database migrations.
- Tailwind CSS standalone CLI `v4.1.10` or compatible.
- `just` for development commands.
- Node.js and npm for frontend unit tests and Playwright e2e tests.
- Optional: `watchexec` for automatic server reloads.

On macOS with Homebrew, a typical setup is:

```bash
brew install rustup postgresql@17 postgis just go node watchexec
rustup-init
go install github.com/jackc/tern/v2@v2.3.2
```

Install Tailwind CSS from the official standalone binary release and make sure
the `tailwindcss` command is available:

```bash
curl -L -o /usr/local/bin/tailwindcss \
  https://github.com/tailwindlabs/tailwindcss/releases/download/v4.1.10/tailwindcss-macos-arm64
chmod +x /usr/local/bin/tailwindcss
```

Use `tailwindcss-macos-x64` instead on Intel Macs. On Linux, use the matching
`tailwindcss-linux-x64` or `tailwindcss-linux-arm64` binary.

### Configuration Directory

The `justfile` expects local config files under `$HOME/.config/ocg` by default.
You can override that path with `OCG_CONFIG`.

```bash
mkdir -p "$HOME/.config/ocg"
```

Create `~/.config/ocg/tern.conf` for migrations:

```toml
[database]
host = 127.0.0.1
port = 5432
database = ocg
user = postgres
password =
```

If your local Postgres user requires a password, set it in this file and export
the same value as `OCG_DB_PASSWORD` when using `just` database commands.

Create `~/.config/ocg/server.yml` for the local server:

```yaml
db:
  host: 127.0.0.1
  port: 5432
  dbname: ocg
  user: postgres
  password: ""
  pool:
    max_size: 25
    timeouts:
      recycle: { secs: 5, nanos: 0 }
      wait: { secs: 5, nanos: 0 }

email:
  from_address: "no-reply@goup.vc"
  from_name: "GOUP Alliance"
  rcpts_whitelist: []
  smtp:
    host: ""
    port: 587
    username: ""
    password: ""

images:
  provider: db

log:
  format: pretty

server:
  addr: 127.0.0.1:9000
  base_url: http://127.0.0.1:9000
  disable_referer_checks: true
  cookie:
    secure: false
  login:
    email: true
    github: false
    linkedin: false
  oauth2: {}
  oidc: {}
```

For LinkedIn login locally, enable it and add your LinkedIn OIDC app details:

```yaml
server:
  login:
    email: false
    github: false
    linkedin: true
  oidc:
    linkedin:
      client_id: "..."
      client_secret: "..."
      issuer_url: https://www.linkedin.com
      redirect_uri: http://127.0.0.1:9000/log-in/oidc/linkedin/callback
      scopes: ["openid", "profile", "email"]
```

The LinkedIn app must allow the exact redirect URI configured above.

### Database Setup

Start PostgreSQL however you normally run it. With Homebrew:

```bash
brew services start postgresql@17
```

Create and migrate the development database:

```bash
just db-create
just db-migrate
```

If you want to reset everything:

```bash
just db-recreate
```

The schema migration enables PostGIS. If migrations fail with
`extension "postgis" is not available`, install the PostGIS package for your
PostgreSQL version and retry.

### Seed Initial Local Data

The migrations create the schema and reference data. For a useful local site,
insert a site, alliance, group category, and group:

```bash
psql -h 127.0.0.1 -p 5432 -U postgres -d ocg <<'SQL'
insert into site (site_id, title, description, theme)
values (
  '00000000-0000-0000-0000-000000000000',
  'GOUP Alliance',
  'GOUP Alliance',
  '{"primary_color":"#0EA5E9"}'
)
on conflict do nothing;

insert into alliance (
  alliance_id,
  name,
  display_name,
  description
) values (
  '11111111-1111-1111-1111-111111111111',
  'goup',
  'GOUP Alliance',
  'GOUP Alliance'
)
on conflict do nothing;

insert into group_category (group_category_id, alliance_id, name)
values (
  '22222222-2222-2222-2222-222222222222',
  '11111111-1111-1111-1111-111111111111',
  'General'
)
on conflict do nothing;

insert into "group" (
  group_id,
  alliance_id,
  group_category_id,
  name,
  slug,
  description
) values (
  '33333333-3333-3333-3333-333333333333',
  '11111111-1111-1111-1111-111111111111',
  '22222222-2222-2222-2222-222222222222',
  'GOUP',
  'goup',
  'GOUP members'
)
on conflict do nothing;
SQL
```

### Run the App

Start the server:

```bash
just server
```

Open the app at:

```text
http://127.0.0.1:9000
```

Run with auto-reload when `watchexec` is installed:

```bash
just server-watch
```

### Run with Docker Compose

If you prefer a containerized local setup, use the development compose file.
It starts PostgreSQL with PostGIS, runs migrations, seeds the initial local
data, and runs the Rust server with file watching enabled.

Build and start the development stack:

```bash
docker compose -f docker-compose.dev.yml up --build
```

Run it in detached mode:

```bash
docker compose -f docker-compose.dev.yml up -d --build
```

Open the app at:

```text
http://127.0.0.1:9000
```

The development server watches the repository for changes and rebuilds on
updates to:

- Rust code under `ocg-server/` and `ocg-redirector/`
- Askama templates under `ocg-server/templates/`
- Frontend JavaScript under `ocg-server/static/js/`
- CSS sources under `ocg-server/static/css/`
- Local server config under `.config/ocg/server.yml`

Useful compose commands:

```bash
docker compose -f docker-compose.dev.yml logs -f server
docker compose -f docker-compose.dev.yml up -d --build seed server
docker compose -f docker-compose.dev.yml down
```

The database data is stored in the named `postgres-data` volume, so it
persists across restarts. To remove the containers and the database volume:

```bash
docker compose -f docker-compose.dev.yml down -v
```

Build without running:

```bash
just server-build
```

Build a release binary:

```bash
cargo build --release -p ocg-server
```

### Remote MCP Server

The `mcp/` directory contains a lightweight remote MCP server for GOUP
operational tools. It supports MCP JSON-RPC over HTTP at `/mcp`, lists tools via
the standard `tools/list` method, and loads tools from `mcp/tools.json`.

Run it locally:

```bash
cd mcp
npm start
```

For remote deployments, protect it with `MCP_BEARER_TOKEN` and expose it behind
HTTPS. See [`mcp/README.md`](./mcp/README.md) for setup, client config, and how
to add more tools.

To set up the remote MCP server on EC2 with a generated bearer token and a
systemd service:

```bash
./scripts/setup-mcp-ec2.sh
```

Enable mutating tools, such as event creation and talk submission, only when the
endpoint is protected behind HTTPS:

```bash
MCP_ENABLE_MUTATIONS=true ./scripts/setup-mcp-ec2.sh
```

The script writes `~/.config/ocg/mcp.env`, starts the `goup-mcp` service, and
prints the NGINX `/mcp` proxy block plus the Cursor/client MCP configuration.

### Tests and Checks

Run Rust server tests:

```bash
just server-tests
```

Run database pgTAP tests:

```bash
just db-tests
```

Run database contract tests:

```bash
just db-contract-tests
```

Run frontend unit tests:

```bash
cd tests/unit
npm ci
npx playwright install
cd ../..
just frontend-unit-tests
```

Run e2e tests:

```bash
just e2e-install
just db-recreate-tests-e2e
just db-load-tests-e2e-data
just e2e-server
```

In another terminal:

```bash
just e2e-tests
```

Format and lint Rust server code:

```bash
just server-fmt-and-lint
```

Format and lint frontend/template code:

```bash
just frontend-fmt-and-lint
```

### GitHub Actions CI/CD

Pull requests to `main` run the relevant CI jobs based on changed paths:

- Rust formatting, clippy, and tests for server changes.
- Database migrations, pgTAP tests, and Rust database contract tests for
  database changes.
- Frontend unit tests and formatting checks for browser JavaScript changes.
- MCP syntax and tool catalog validation for files under `mcp/`.
- Playwright e2e suites when app, database, or e2e files change.

Pushes to `main` publish Docker images to GitHub Container Registry under this
repository:

```text
ghcr.io/sakomws/goup.vc/server
ghcr.io/sakomws/goup.vc/redirector
ghcr.io/sakomws/goup.vc/dbmigrator
```

Images are tagged with `sha-<commit>` and `latest` on `main`. The workflow uses
the built-in `GITHUB_TOKEN`; no Oracle/OCI registry secrets are required.

The production EC2 deployment is still updated by pulling from Git and
restarting systemd services, as documented below.

### Common Development Workflow

For a fresh local checkout:

```bash
git clone https://github.com/sakomws/goup.vc.git
cd goup.vc
mkdir -p "$HOME/.config/ocg"
# Create tern.conf and server.yml from the examples above.
just db-create
just db-migrate
just server
```

After pulling code changes:

```bash
git pull
just db-migrate
just server
```

If the change only touches templates, Rust code, CSS, or JavaScript, you can
usually skip migrations. If database files under `database/migrations` changed,
run `just db-migrate`.

### EC2 Deployment Helper

For a fresh EC2 deployment, use the bootstrap script. It installs common
dependencies, writes config, runs migrations, seeds initial GOUP records, builds
the release binary, and installs a systemd service.

```bash
OCG_DB_PASSWORD='replace-with-a-strong-password' \
OCG_LINKEDIN_CLIENT_ID='replace-with-linkedin-client-id' \
OCG_LINKEDIN_CLIENT_SECRET='replace-with-linkedin-client-secret' \
OCG_ADMIN_EMAIL='you@example.com' \
./scripts/bootstrap-ec2.sh
```

### Update an Existing EC2 Deployment

After pulling new code on EC2, run migrations before rebuilding and restarting
whenever files under `database/migrations` changed. The migration script lives
under `database/migrations`, so do not run `./migrate.sh` from the repository
root:

```bash
cd ~/goup.vc
git pull

cd database/migrations
TERN_CONF="$HOME/.config/ocg/tern.conf" ./migrate.sh
```

Or run the same migration from the repository root:

```bash
cd ~/goup.vc
TERN_CONF="$HOME/.config/ocg/tern.conf" ./database/migrations/migrate.sh
```

Build the release binary in the background so it keeps running if the SSH
session disconnects, then restart the deployed service after the build finishes
successfully:

```bash
cd ~/goup.vc
nohup env CARGO_BUILD_JOBS=1 cargo build --release -p ocg-server > ~/goup-build.log 2>&1 &
tail -f ~/goup-build.log

sudo systemctl restart ocg-server
sudo systemctl status ocg-server --no-pager
curl -I http://127.0.0.1:9000
```

For small EC2 instances, keep builds single-threaded:

```bash
CARGO_BUILD_JOBS=1 cargo build --release -p ocg-server
```

If files under `mcp/` changed, restart the remote MCP service too:

```bash
sudo systemctl restart goup-mcp
sudo systemctl status goup-mcp --no-pager
```

### Troubleshooting

If `cargo build` fails with `tailwindcss not found in PATH`, install the
standalone Tailwind CSS binary and retry.

If migrations fail with `tern: command not found`, install it with:

```bash
go install github.com/jackc/tern/v2@v2.3.2
export PATH="$HOME/go/bin:$PATH"
```

If local login redirects behave strangely, confirm that `server.base_url`,
cookie settings, and provider redirect URIs match the URL you use in the
browser.

If Playwright tests fail because the browser executable is missing, run:

```bash
cd tests/unit
npx playwright install
```

For EC2 logs:

```bash
sudo journalctl -u ocg-server -n 100 --no-pager
sudo journalctl -u nginx -n 100 --no-pager
```

## Contributing

Please see [CONTRIBUTING.md](./CONTRIBUTING.md) for more details.

## Code of Conduct

This project follows the [Goup Code of Conduct](https://github.com/goup/foundation/blob/master/code-of-conduct.md).

## License

GOUP Alliance is an open source project licensed under the
[Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0).
