import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { spawn } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const PORT = Number.parseInt(process.env.PORT || process.env.MCP_PORT || "8787", 10);
const HOST = process.env.HOST || process.env.MCP_HOST || "0.0.0.0";
const BEARER_TOKEN = process.env.MCP_BEARER_TOKEN || "";
const ENABLE_MUTATIONS = process.env.MCP_ENABLE_MUTATIONS === "true";
const PROTOCOL_VERSION = "2024-11-05";
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const WIKI_SECTIONS = [
  {
    id: "ai",
    title: "AI",
    sources: [
      { label: "arXiv AI", url: "https://export.arxiv.org/rss/cs.AI" },
      { label: "Google AI", url: "https://blog.google/technology/ai/rss/" },
      { label: "Simon Willison Blog", url: "https://simonwillison.net/atom/everything/" },
      { label: "Hugging Face Blog", url: "https://huggingface.co/blog/feed.xml" },
      { label: "Latent Space", url: "https://www.latent.space/feed" },
      { label: "Import AI", url: "https://importai.substack.com/feed" },
      { label: "The Batch by DeepLearning.AI", url: "https://www.deeplearning.ai/the-batch/feed/" },
      { label: "OpenAI", url: "https://openai.com/news/rss.xml" },
      { label: "Anthropic News", url: "https://www.anthropic.com/news/rss.xml" },
      { label: "InfoQ AI/ML", url: "https://feed.infoq.com/AI-ML-Data-Engineering" },
      { label: "LlamaIndex Blog", url: "https://www.llamaindex.ai/blog/rss.xml" },
      { label: "LangChain Blog", url: "https://blog.langchain.com/rss/" },
      { label: "a16z AI", url: "https://a16z.news/feed" },
      { label: "Papers with Code Trending", url: "https://paperswithcode.com/rss.xml" },
    ],
  },
  {
    id: "opensource",
    title: "Open Source",
    sources: [
      { label: "GitHub Blog", url: "https://github.blog/feed/" },
      { label: "CNCF", url: "https://www.cncf.io/feed/" },
      { label: "Hacker News Front Page RSS", url: "https://hnrss.org/frontpage" },
      { label: "GitHub Trending RSS", url: "https://mshibanami.github.io/GitHubTrendingRSS/daily/all.xml" },
    ],
  },
  {
    id: "entrepreneurship",
    title: "Entrepreneurship",
    sources: [
      { label: "Y Combinator Blog", url: "https://www.ycombinator.com/blog/rss.xml" },
      { label: "TechCrunch Startups", url: "https://techcrunch.com/category/startups/feed/" },
      { label: "Lenny's Newsletter", url: "https://www.lennysnewsletter.com/feed" },
      { label: "Sequoia Capital Blog", url: "https://www.sequoiacap.com/feed/" },
      { label: "Paul Graham Essays", url: "https://paulgraham.com/index.xml" },
    ],
  },
];

const jsonHeaders = {
  "Access-Control-Allow-Headers": "authorization, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Origin": "*",
  "Content-Type": "application/json; charset=utf-8",
};

const tools = await loadTools();

const server = createServer(async (req, res) => {
  try {
    if (req.method === "OPTIONS") {
      writeJson(res, 204, null);
      return;
    }

    if (!isAuthorized(req)) {
      writeJson(res, 401, { error: "unauthorized" });
      return;
    }

    if (req.method === "GET" && req.url === "/health") {
      writeJson(res, 200, { status: "ok", tools: tools.length });
      return;
    }

    if (req.method === "GET" && req.url === "/tools") {
      writeJson(res, 200, { tools: listTools() });
      return;
    }

    if (req.method === "POST" && req.url === "/mcp") {
      const body = await readJsonBody(req);
      const response = Array.isArray(body)
        ? (await Promise.all(body.map(handleJsonRpc))).filter(Boolean)
        : await handleJsonRpc(body);

      if (!response || (Array.isArray(response) && response.length === 0)) {
        writeJson(res, 202, null);
        return;
      }

      writeJson(res, 200, response);
      return;
    }

    writeJson(res, 404, { error: "not found" });
  } catch (error) {
    writeJson(res, 500, { error: error.message || "internal server error" });
  }
});

server.listen(PORT, HOST, () => {
  console.log(`GOUP MCP server listening on http://${HOST}:${PORT}/mcp`);
});

async function loadTools() {
  const raw = await readFile(join(__dirname, "tools.json"), "utf8");
  const parsed = JSON.parse(raw);

  if (!Array.isArray(parsed)) {
    throw new Error("tools.json must contain an array");
  }

  return parsed.map((tool) => {
    if (!tool.name || !tool.description || !tool.inputSchema) {
      throw new Error("each tool must define name, description, and inputSchema");
    }

    if (!tool.output?.text && !tool.action) {
      throw new Error("each tool must define output.text or action");
    }

    return tool;
  });
}

function isAuthorized(req) {
  if (!BEARER_TOKEN) {
    return true;
  }

  return req.headers.authorization === `Bearer ${BEARER_TOKEN}`;
}

function listTools() {
  return tools.map(({ name, title, description, inputSchema }) => ({
    name,
    title,
    description,
    inputSchema,
  }));
}

async function handleJsonRpc(message) {
  if (!message || message.jsonrpc !== "2.0" || !message.method) {
    return jsonRpcError(message?.id ?? null, -32600, "Invalid Request");
  }

  const { id, method, params } = message;

  if (method === "notifications/initialized") {
    return null;
  }

  if (id === undefined || id === null) {
    return null;
  }

  switch (method) {
    case "initialize":
      return jsonRpcResult(id, {
        protocolVersion: PROTOCOL_VERSION,
        capabilities: {
          tools: {
            listChanged: false,
          },
        },
        serverInfo: {
          name: "goup-vc-mcp",
          version: "0.1.0",
        },
      });

    case "tools/list":
      return jsonRpcResult(id, { tools: listTools() });

    case "tools/call":
      return callTool(id, params);

    case "prompts/list":
      return jsonRpcResult(id, { prompts: [] });

    case "resources/list":
      return jsonRpcResult(id, { resources: [] });

    default:
      return jsonRpcError(id, -32601, `Method not found: ${method}`);
  }
}

async function callTool(id, params = {}) {
  const tool = tools.find((item) => item.name === params.name);

  if (!tool) {
    return jsonRpcError(id, -32602, `Unknown tool: ${params.name}`);
  }

  if (tool.action) {
    try {
      return jsonRpcResult(id, {
        content: [
          {
            type: "text",
            text: await runAction(tool.action, params.arguments || {}),
          },
        ],
        isError: false,
      });
    } catch (error) {
      return jsonRpcResult(id, {
        content: [
          {
            type: "text",
            text: error.message || "tool failed",
          },
        ],
        isError: true,
      });
    }
  }

  return jsonRpcResult(id, {
    content: [
      {
        type: "text",
        text: renderToolOutput(tool, params.arguments || {}),
      },
    ],
    isError: false,
  });
}

async function runAction(action, args) {
  switch (action) {
    case "create_event":
      return createEvent(args);
    case "search_groups":
      return searchGroups(args);
    case "search_events":
      return searchEvents(args);
    case "search_members":
      return searchMembers(args);
    case "search_teams":
      return searchTeams(args);
    case "search_jobs":
      return searchJobs(args);
    case "search_landscape":
      return searchLandscape(args);
    case "search_wiki":
      return searchWiki(args);
    case "submit_talk":
      return submitTalk(args);
    default:
      throw new Error(`Unknown tool action: ${action}`);
  }
}

async function searchJobs(args) {
  const filters = {
    query: optionalString(args.query),
    location: optionalString(args.location),
    remote: typeof args.remote === "boolean" ? args.remote : undefined,
    limit: normalizeLimit(args.limit),
    offset: normalizeOffset(args.offset),
  };
  const sql = sqlWithJsonArgs(filters, `
select search_jobs(j)::text from args;
`);

  return (await runPsql(sql)).trim();
}

async function searchLandscape(args) {
  const filters = {
    query: optionalString(args.query),
    kind: optionalString(args.kind),
    category: optionalString(args.category),
    alliance: optionalString(args.alliance || args.alliance_name),
    limit: normalizeLimit(args.limit),
    offset: normalizeOffset(args.offset),
  };
  const sql = sqlWithJsonArgs(filters, `
select search_landscape_entries(j)::text from args;
`);

  return (await runPsql(sql)).trim();
}

async function searchWiki(args) {
  const query = optionalString(args.query)?.toLowerCase();
  const section = optionalString(args.section)?.toLowerCase();
  const limit = normalizeLimit(args.limit);
  const rows = [];

  for (const wikiSection of WIKI_SECTIONS) {
    if (section && wikiSection.id !== section && wikiSection.title.toLowerCase() !== section) {
      continue;
    }

    for (const source of wikiSection.sources) {
      const haystack = `${wikiSection.id} ${wikiSection.title} ${source.label} ${source.url}`.toLowerCase();
      if (!query || haystack.includes(query)) {
        rows.push({
          section_id: wikiSection.id,
          section_title: wikiSection.title,
          source_label: source.label,
          source_url: source.url,
        });
      }
    }
  }

  return JSON.stringify(rows.slice(0, limit));
}

async function submitTalk(args) {
  if (!ENABLE_MUTATIONS) {
    throw new Error("Mutating MCP tools are disabled. Set MCP_ENABLE_MUTATIONS=true to allow talk submissions.");
  }

  const actorUserId = requireUuid(args.actor_user_id, "actor_user_id");
  const allianceId = requireUuid(args.alliance_id, "alliance_id");
  const eventId = requireUuid(args.event_id, "event_id");
  const labelIds = Array.isArray(args.label_ids) ? args.label_ids.map((id) => requireUuid(id, "label_ids")) : [];
  const proposal = {
    title: requireString(args.title, "title"),
    description: requireString(args.description, "description"),
    duration_minutes: normalizeDuration(args.duration_minutes),
    session_proposal_level_id: requireProposalLevel(args.session_proposal_level_id || "intermediate"),
    co_speaker_user_id: args.co_speaker_user_id ? requireUuid(args.co_speaker_user_id, "co_speaker_user_id") : "",
  };
  const proposalJsonBase64 = Buffer.from(JSON.stringify(proposal), "utf8").toString("base64");
  const labelArray = labelIds.length
    ? `array[${labelIds.map((id) => `'${id}'::uuid`).join(", ")}]`
    : "array[]::uuid[]";

  const sql = `
with proposal as (
  select add_session_proposal(
    '${actorUserId}'::uuid,
    convert_from(decode('${proposalJsonBase64}', 'base64'), 'UTF8')::jsonb
  ) as session_proposal_id
),
submission as (
  select add_cfs_submission(
    '${allianceId}'::uuid,
    '${eventId}'::uuid,
    '${actorUserId}'::uuid,
    proposal.session_proposal_id,
    ${labelArray}
  ) as cfs_submission_id,
  proposal.session_proposal_id
  from proposal
)
select json_build_object(
  'session_proposal_id', session_proposal_id,
  'cfs_submission_id', cfs_submission_id,
  'status', 'submitted'
)::text
from submission;
`;

  return (await runPsql(sql)).trim();
}

async function searchGroups(args) {
  const filters = buildSearchFilters(args);
  const sql = sqlWithJsonArgs(filters, `
, rows as (
  select
    a.alliance_id,
    a.name as alliance_name,
    a.display_name as alliance_display_name,
    g.group_id,
    g.name,
    coalesce(g.slug_pretty, g.slug) as slug,
    gc.name as category,
    g.active,
    g.city,
    g.country_name,
    g.description_short,
    (select count(*)::int from group_member gm where gm.group_id = g.group_id) as member_count,
    (select count(*)::int from event e where e.group_id = g.group_id and e.deleted = false) as event_count
  from "group" g
  join alliance a on a.alliance_id = g.alliance_id
  join group_category gc on gc.group_category_id = g.group_category_id
  cross join args
  where g.deleted = false
    and (args.j->>'alliance_id' is null or a.alliance_id::text = args.j->>'alliance_id')
    and (args.j->>'alliance_name' is null or a.name = args.j->>'alliance_name')
    and (
      args.j->>'query' is null
      or concat_ws(' ', g.name, g.slug, g.slug_pretty, g.description, g.description_short, g.city, g.state, g.country_name, gc.name)
         ilike '%' || (args.j->>'query') || '%'
    )
  order by lower(g.name), g.group_id
  limit (select (j->>'limit')::int from args)
)
select coalesce(json_agg(row_to_json(rows)), '[]'::json)::text from rows;
`);

  return (await runPsql(sql)).trim();
}

async function searchEvents(args) {
  const filters = buildSearchFilters(args);
  const sql = sqlWithJsonArgs(filters, `
, rows as (
  select
    a.alliance_id,
    a.name as alliance_name,
    g.group_id,
    g.name as group_name,
    coalesce(g.slug_pretty, g.slug) as group_slug,
    e.event_id,
    e.name,
    e.slug,
    e.published,
    e.canceled,
    e.test_event,
    e.event_kind_id as kind_id,
    ek.display_name as kind,
    ec.name as category,
    e.timezone,
    e.starts_at,
    e.ends_at,
    e.venue_city,
    e.venue_country_name,
    e.description_short
  from event e
  join "group" g on g.group_id = e.group_id
  join alliance a on a.alliance_id = g.alliance_id
  join event_category ec on ec.event_category_id = e.event_category_id
  join event_kind ek on ek.event_kind_id = e.event_kind_id
  cross join args
  where e.deleted = false
    and (args.j->>'alliance_id' is null or a.alliance_id::text = args.j->>'alliance_id')
    and (args.j->>'alliance_name' is null or a.name = args.j->>'alliance_name')
    and (args.j->>'group_id' is null or g.group_id::text = args.j->>'group_id')
    and (args.j->>'published' is null or e.published = (args.j->>'published')::boolean)
    and (
      args.j->>'query' is null
      or concat_ws(' ', e.name, e.slug, e.description, e.description_short, e.tags, e.venue_name, e.venue_city, ec.name, ek.display_name)
         ilike '%' || (args.j->>'query') || '%'
    )
  order by e.starts_at nulls last, e.created_at desc, e.event_id
  limit (select (j->>'limit')::int from args)
)
select coalesce(json_agg(row_to_json(rows)), '[]'::json)::text from rows;
`);

  return (await runPsql(sql)).trim();
}

async function searchMembers(args) {
  const filters = buildSearchFilters(args);
  const sql = sqlWithJsonArgs(filters, `
, rows as (
  select
    a.alliance_id,
    a.name as alliance_name,
    g.group_id,
    g.name as group_name,
    coalesce(g.slug_pretty, g.slug) as group_slug,
    u.user_id,
    u.username,
    u.email,
    u.name,
    u.title,
    u.company,
    u.city,
    u.country,
    u.linkedin_url,
    coalesce(u.provider ? 'linkedin', false) as linkedin_connected,
    gm.created_at as joined_at
  from group_member gm
  join "group" g on g.group_id = gm.group_id
  join alliance a on a.alliance_id = g.alliance_id
  join "user" u on u.user_id = gm.user_id
  cross join args
  where g.deleted = false
    and (args.j->>'alliance_id' is null or a.alliance_id::text = args.j->>'alliance_id')
    and (args.j->>'alliance_name' is null or a.name = args.j->>'alliance_name')
    and (args.j->>'group_id' is null or g.group_id::text = args.j->>'group_id')
    and (
      args.j->>'query' is null
      or concat_ws(' ', u.email, u.username, u.name, u.title, u.company, u.city, u.country, u.linkedin_url, g.name)
         ilike '%' || (args.j->>'query') || '%'
    )
  order by lower(coalesce(u.name, u.username)), u.user_id
  limit (select (j->>'limit')::int from args)
)
select coalesce(json_agg(row_to_json(rows)), '[]'::json)::text from rows;
`);

  return (await runPsql(sql)).trim();
}

async function searchTeams(args) {
  const filters = buildSearchFilters(args);
  const scope = args.scope || "all";
  if (!["alliance", "group", "all"].includes(scope)) {
    throw new Error("scope must be one of: alliance, group, all");
  }
  filters.scope = scope;

  const sql = sqlWithJsonArgs(filters, `
, group_rows as (
  select
    'group' as scope,
    a.alliance_id,
    a.name as alliance_name,
    g.group_id,
    g.name as group_name,
    coalesce(g.slug_pretty, g.slug) as group_slug,
    u.user_id,
    u.username,
    u.email,
    u.name,
    u.title,
    u.company,
    gt.role,
    gt.accepted,
    gt.created_at
  from group_team gt
  join "group" g on g.group_id = gt.group_id
  join alliance a on a.alliance_id = g.alliance_id
  join "user" u on u.user_id = gt.user_id
  cross join args
  where g.deleted = false
    and args.j->>'scope' in ('group', 'all')
    and (args.j->>'alliance_id' is null or a.alliance_id::text = args.j->>'alliance_id')
    and (args.j->>'alliance_name' is null or a.name = args.j->>'alliance_name')
    and (args.j->>'group_id' is null or g.group_id::text = args.j->>'group_id')
    and (
      args.j->>'query' is null
      or concat_ws(' ', u.email, u.username, u.name, u.title, u.company, gt.role, g.name)
         ilike '%' || (args.j->>'query') || '%'
    )
),
alliance_rows as (
  select
    'alliance' as scope,
    a.alliance_id,
    a.name as alliance_name,
    null::uuid as group_id,
    null::text as group_name,
    null::text as group_slug,
    u.user_id,
    u.username,
    u.email,
    u.name,
    u.title,
    u.company,
    at.role,
    at.accepted,
    at.created_at
  from alliance_team at
  join alliance a on a.alliance_id = at.alliance_id
  join "user" u on u.user_id = at.user_id
  cross join args
  where args.j->>'scope' in ('alliance', 'all')
    and (args.j->>'alliance_id' is null or a.alliance_id::text = args.j->>'alliance_id')
    and (args.j->>'alliance_name' is null or a.name = args.j->>'alliance_name')
    and (args.j->>'group_id' is null)
    and (
      args.j->>'query' is null
      or concat_ws(' ', u.email, u.username, u.name, u.title, u.company, at.role, a.name)
         ilike '%' || (args.j->>'query') || '%'
    )
),
rows as (
  select * from group_rows
  union all
  select * from alliance_rows
  order by scope, lower(coalesce(name, username)), user_id
  limit (select (j->>'limit')::int from args)
)
select coalesce(json_agg(row_to_json(rows)), '[]'::json)::text from rows;
`);

  return (await runPsql(sql)).trim();
}

async function createEvent(args) {
  if (!ENABLE_MUTATIONS) {
    throw new Error("Mutating MCP tools are disabled. Set MCP_ENABLE_MUTATIONS=true to allow event creation.");
  }

  const event = buildEventPayload(args);
  const eventJsonBase64 = Buffer.from(JSON.stringify(event), "utf8").toString("base64");
  const actorUserId = requireUuid(args.actor_user_id, "actor_user_id");
  const groupId = requireUuid(args.group_id, "group_id");

  const sql = `
with created as (
  select add_event(
    '${actorUserId}'::uuid,
    '${groupId}'::uuid,
    convert_from(decode('${eventJsonBase64}', 'base64'), 'UTF8')::jsonb,
    '{}'::jsonb
  ) as event_id
)
select json_build_object(
  'event_id', event_id,
  'status', 'draft',
  'message', 'Event created as an unpublished draft.'
)::text
from created;
`;

  const output = await runPsql(sql);
  return output.trim();
}

function buildSearchFilters(args) {
  const filters = {
    limit: normalizeLimit(args.limit),
  };

  for (const key of ["alliance_id", "group_id"]) {
    if (args[key] !== undefined && args[key] !== null && args[key] !== "") {
      filters[key] = requireUuid(args[key], key);
    }
  }

  for (const key of ["alliance_name", "query"]) {
    if (typeof args[key] === "string" && args[key].trim()) {
      filters[key] = args[key].trim();
    }
  }

  if (typeof args.published === "boolean") {
    filters.published = args.published;
  }

  return filters;
}

function normalizeLimit(value) {
  if (value === undefined || value === null) {
    return 20;
  }

  if (!Number.isInteger(value) || value < 1 || value > 100) {
    throw new Error("limit must be an integer from 1 to 100");
  }

  return value;
}

function normalizeOffset(value) {
  if (value === undefined || value === null) {
    return 0;
  }

  if (!Number.isInteger(value) || value < 0) {
    throw new Error("offset must be a non-negative integer");
  }

  return value;
}

function normalizeDuration(value) {
  if (!Number.isInteger(value) || value < 5 || value > 480) {
    throw new Error("duration_minutes must be an integer from 5 to 480");
  }

  return value;
}

function optionalString(value) {
  if (typeof value !== "string") {
    return undefined;
  }

  const trimmed = value.trim();
  return trimmed ? trimmed : undefined;
}

function requireProposalLevel(value) {
  if (!["beginner", "intermediate", "advanced"].includes(value)) {
    throw new Error("session_proposal_level_id must be one of: beginner, intermediate, advanced");
  }

  return value;
}

function sqlWithJsonArgs(args, bodySql) {
  const encodedArgs = Buffer.from(JSON.stringify(args), "utf8").toString("base64");
  return `
with args as (
  select convert_from(decode('${encodedArgs}', 'base64'), 'UTF8')::jsonb as j
)
${bodySql}
`;
}

function buildEventPayload(args) {
  const name = requireString(args.name, "name");
  const description = requireString(args.description, "description");
  const timezone = args.timezone || "Asia/Baku";
  const startsAt = requireString(args.starts_at, "starts_at");
  const endsAt = requireString(args.ends_at, "ends_at");
  const kindId = requireEventKind(args.kind_id || "in-person");

  return {
    name,
    description,
    description_short: args.description_short || "",
    timezone,
    starts_at: startsAt,
    ends_at: endsAt,
    category_id: requireUuid(args.category_id, "category_id"),
    kind_id: kindId,
    capacity: args.capacity ?? null,
    registration_required: Boolean(args.registration_required),
    attendee_approval_required: Boolean(args.attendee_approval_required),
    waitlist_enabled: Boolean(args.waitlist_enabled),
    test_event: Boolean(args.test_event),
    event_reminder_enabled: args.event_reminder_enabled ?? true,
    cfs_enabled: false,
    cfs_labels: [],
    discount_codes: null,
    meeting_hosts: [],
    meeting_join_instructions: "",
    meeting_join_url: args.meeting_join_url || "",
    meeting_provider_id: "",
    meeting_recording_published: false,
    meeting_recording_requested: false,
    meeting_recording_url: "",
    meeting_requested: false,
    meetup_url: args.meetup_url || "",
    luma_url: args.luma_url || "",
    payment_currency_code: "",
    photos_urls: [],
    registration_questions: [],
    sessions: [],
    tags: Array.isArray(args.tags) ? args.tags : [],
    venue_address: args.venue_address || "",
    venue_city: args.venue_city || "",
    venue_country_code: args.venue_country_code || "",
    venue_country_name: args.venue_country_name || "",
    venue_name: args.venue_name || "",
    venue_state: args.venue_state || "",
    venue_zip_code: args.venue_zip_code || "",
  };
}

function requireUuid(value, name) {
  if (typeof value !== "string" || !UUID_RE.test(value)) {
    throw new Error(`${name} must be a UUID`);
  }

  return value;
}

function requireString(value, name) {
  if (typeof value !== "string" || !value.trim()) {
    throw new Error(`${name} is required`);
  }

  return value.trim();
}

function requireEventKind(value) {
  if (!["in-person", "virtual", "hybrid"].includes(value)) {
    throw new Error("kind_id must be one of: in-person, virtual, hybrid");
  }

  return value;
}

async function runPsql(sql) {
  const { args, env } = await buildPsqlCommand();

  return new Promise((resolve, reject) => {
    const child = spawn("psql", [...args, "-X", "-A", "-t", "-v", "ON_ERROR_STOP=1", "-c", sql], {
      env,
      stdio: ["ignore", "pipe", "pipe"],
    });
    const stdout = [];
    const stderr = [];

    child.stdout.on("data", (chunk) => stdout.push(chunk));
    child.stderr.on("data", (chunk) => stderr.push(chunk));
    child.on("error", reject);
    child.on("close", (code) => {
      if (code === 0) {
        resolve(Buffer.concat(stdout).toString("utf8"));
        return;
      }

      reject(new Error(Buffer.concat(stderr).toString("utf8").trim() || `psql exited with code ${code}`));
    });
  });
}

async function buildPsqlCommand() {
  if (process.env.DATABASE_URL) {
    return {
      args: [process.env.DATABASE_URL],
      env: process.env,
    };
  }

  const configPath = process.env.TERN_CONF || join(process.env.HOME || "", ".config/ocg/tern.conf");
  const config = await readTernConfig(configPath);
  const args = [];

  if (config.host) args.push("-h", config.host);
  if (config.port) args.push("-p", config.port);
  if (config.user) args.push("-U", config.user);
  if (config.database) args.push("-d", config.database);

  return {
    args,
    env: {
      ...process.env,
      PGPASSWORD: process.env.PGPASSWORD || config.password || "",
    },
  };
}

async function readTernConfig(path) {
  const raw = await readFile(path, "utf8");
  const config = {};
  let inDatabaseSection = false;

  for (const line of raw.split("\n")) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    if (trimmed.startsWith("[")) {
      inDatabaseSection = trimmed === "[database]";
      continue;
    }
    if (!inDatabaseSection) continue;

    const match = trimmed.match(/^([A-Za-z0-9_]+)\s*=\s*(.*)$/);
    if (!match) continue;

    config[match[1]] = match[2].replace(/^"(.*)"$/, "$1");
  }

  return config;
}

function renderToolOutput(tool, args) {
  return tool.output.text.replace(/\{\{\s*([a-zA-Z0-9_]+)\s*\}\}/g, (_, key) => {
    const value = args[key];
    return value === undefined || value === null ? "" : String(value);
  });
}

async function readJsonBody(req) {
  const chunks = [];

  for await (const chunk of req) {
    chunks.push(chunk);
  }

  const raw = Buffer.concat(chunks).toString("utf8");
  return raw ? JSON.parse(raw) : null;
}

function jsonRpcResult(id, result) {
  return {
    jsonrpc: "2.0",
    id,
    result,
  };
}

function jsonRpcError(id, code, message) {
  return {
    jsonrpc: "2.0",
    id,
    error: {
      code,
      message,
    },
  };
}

function writeJson(res, statusCode, body) {
  res.writeHead(statusCode, jsonHeaders);
  if (body !== null) {
    res.end(JSON.stringify(body));
    return;
  }

  res.end();
}
