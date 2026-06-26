<!-- markdownlint-disable MD013 -->

# Project Contributors Runbook

Use this runbook if you contribute projects to GOUP, maintain project listings, or work on the GOUP
application as a developer.

## Contributor Paths

There are two common contributor paths:

- **Project contributor:** You want to share or maintain a project in the GOUP ecosystem, usually through an alliance landscape or group program.
- **Application contributor:** You want to improve the GOUP application, docs, database, templates, tests, or deployment tooling.

For code architecture details, read the [Development Guide](../development.md).

## Add or Maintain a Project

Projects should be useful to the community and easy for members to evaluate.

Before adding a project, collect:

- Project name.
- Short description.
- Website or repository URL.
- Tags or categories.
- Maintainer or organization context.
- GitHub URL when the project is hosted on GitHub.

When a GitHub URL is available, GOUP can display repository metadata such as owner, repository name,
stars, forks, watchers, and open issues where that feature is enabled.

Good project entries:

- Explain what the project does in plain language.
- Link to a maintained source, website, or documentation page.
- Use tags that help people discover it.
- Avoid marketing-only descriptions.
- Stay current when ownership, URLs, or status changes.

## Project Listing Review Checklist

Use this checklist before publishing or requesting review:

1. The project has a working URL.
2. The description explains user value, not only internal implementation.
3. Tags are relevant and not excessive.
4. The project owner or maintainer is clear.
5. GitHub metadata points to the canonical repository.
6. The project does not impersonate another organization.
7. The listing is appropriate for the alliance or group audience.

## Contribute to GOUP Code

GOUP is a Rust server-rendered application with PostgreSQL, Askama templates, HTMX, and focused
client-side JavaScript.

Recommended local flow:

1. Read [Development Guide](../development.md).
2. Create a branch for one focused change.
3. Make the smallest change that solves the user problem.
4. Add or update focused tests.
5. Run the checks that match the risk.
6. Open a pull request with a clear summary and test plan.

Use existing patterns before adding new abstractions:

- Handlers live in `ocg-server/src/handlers/`.
- Template view models live in `ocg-server/src/templates/`.
- Askama HTML templates live in `ocg-server/templates/`.
- Database functions live in `database/migrations/functions/`.
- Schema migrations live in `database/migrations/schema/`.
- Docs live in `docs/`.

## Testing Checklist for App Contributors

Use focused tests first, then broaden when behavior is shared.

Common checks:

```bash
cargo fmt --all -- --check
cargo check -p ocg-server
cargo clippy -p ocg-server --all-targets --all-features -- --deny warnings
cargo test -p ocg-server
uvx --python 3.12 djlint==1.39.2 --check --configuration ocg-server/templates/.djlintrc ocg-server/templates
npx markdownlint-cli2 "**/*.md"
```

Database changes may also require:

```bash
just db-tests
just db-contract-tests
```

Browser-facing changes may require:

```bash
just frontend-unit-tests
just e2e-tests
```

## Pull Request Checklist

Before asking for review:

- Keep the PR focused on one problem.
- Include screenshots for visible UI changes when helpful.
- Include migrations, generated mocks, and tests when behavior changes.
- Mention any operational steps reviewers or deployers need to know.
- Avoid unrelated formatting or ownership churn.
- Confirm docs are updated when user-facing behavior changes.

## Safety Rules

Protect community trust:

- Do not expose private member data in public pages, logs, or docs.
- Do not weaken role checks to make a UI easier to implement.
- Do not send email from public forms without authentication or spam controls.
- Do not make project metadata look official unless the maintainers approved it.
- Do not publish secrets, access tokens, `.env` values, or private credentials.

## Maintenance Runbook

For ongoing project and app health:

- Review stale project listings periodically.
- Remove or update broken project links.
- Keep docs aligned with the shipped UI.
- Watch CI after merging PRs.
- Prefer small follow-up PRs over large mixed changes.
- Use the audit logs and dashboard tests to debug permission-sensitive behavior.
