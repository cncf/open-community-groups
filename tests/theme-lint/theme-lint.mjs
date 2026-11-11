import { readFileSync, readdirSync } from "node:fs";
import { dirname, join, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

// Guards the color theme token architecture: templates, static JS and styles.src.css paint
// through `--color-*` tokens, never raw white or black, unmapped hues, numbered primary shades,
// color literals or the light and dark color sources. Each remapped palette shade they use
// (stone 50-900, status 50-200 and 700-950) needs an `--ocg-light-*` constant in styles.src.css,
// or it stays light in dark. The token blocks themselves are checked by the Rust tests in
// ocg-server/src/templates/brand_ramp/tests.rs and templates/tests.rs.
//
// Class tokens are scanned in the whole text of every template and JS file, plus the `@apply`
// statements of styles.src.css. Inside `/* theme-lint: tokens-start <reason> */ ...
// /* theme-lint: tokens-end */` regions, CSS literals, custom property reads and arbitrary
// colors in `@apply` are allowed, but remapped shades still need their constant. Other
// exemptions live in theme-lint-allowlist.json as `{ file, rule, match, count, reason }`
// entries, where `<N>` in `match` stands for a shade number.
//
// Prints one `path:line: rule: message` line per finding without an allowlist entry, per stale
// or malformed allowlist entry and per `token-region` marker error (an unmatched marker, a
// missing reason, nesting), and exits with status 1 when it prints any. Run by
// `just frontend-fmt-and-lint` and the CI `lint-theme-colors` job.
//
// Usage: theme-lint.mjs

const ALLOWLIST_FIELDS = ["count", "file", "match", "reason", "rule"];
const ALLOWLIST_PATH = "tests/theme-lint/theme-lint-allowlist.json";
const ARBITRARY_FUNCTION_PATTERN = /-\[(?:rgba?|hsla?|oklch|oklab|color-mix)\(/u;
const ARBITRARY_HEX_PATTERN = /-\[#[0-9a-fA-F]{3,8}[\]/]/u;
const BANNED_HUES = [
  "blue",
  "cyan",
  "fuchsia",
  "gray",
  "indigo",
  "lime",
  "neutral",
  "pink",
  "purple",
  "rose",
  "sky",
  "slate",
  "teal",
  "violet",
  "zinc",
];
const BANNED_HUE_READ_PATTERN = new RegExp(`^--color-(${BANNED_HUES.join("|")})-\\d+$`, "u");
const BANNED_HUE_UTILITY_PATTERN = new RegExp(`^[a-z][a-z-]*-(${BANNED_HUES.join("|")})-\\d+$`, "u");
const COLOR_FUNCTION_PATTERN = /(?<![\w-])(?:rgba?|hsla?|oklch|oklab)\(/gu;
const COLOR_KEYWORD_PATTERN = /(?<![\w-])(?:white|black)(?![\w-])/gu;
const COLOR_UTILITY_PREFIX =
  "(?:bg|text|border(?:-[xytrblse])?|ring|ring-offset|outline|divide|from|via|to|fill|stroke|decoration|accent|caret|placeholder|shadow)";
const CSS_PATH = "ocg-server/static/css/styles.src.css";
const HEX_PATTERN = /(?<![&\w#])#(?:[0-9a-fA-F]{8}|[0-9a-fA-F]{6}|[0-9a-fA-F]{3,4})(?![\w-])/gu;
const LIGHT_CONSTANT_PATTERN = /--ocg-light-([a-z]+-\d+)\s*:/gu;
const MARKER_PATTERN = /\/\*\s*theme-lint:([\s\S]*?)\*\//gu;
const PALETTE_HUES = ["amber", "emerald", "green", "orange", "red", "stone", "yellow"];
const PALETTE_SHADE_READ_PATTERN = new RegExp(`^--color-((?:${PALETTE_HUES.join("|")})-\\d+)$`, "u");
const PALETTE_SHADE_UTILITY_PATTERN = new RegExp(`^[a-z][a-z-]*-((?:${PALETTE_HUES.join("|")})-\\d+)$`, "u");
const RAW_WHITE_BLACK_PATTERN = new RegExp(`^${COLOR_UTILITY_PREFIX}-(?:white|black)$`, "u");
const READ_PATTERN = /(?:(var\(|-\()\s*|(["'`]))(--[\w-]+)/gu;
const REPO_DIR = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const RULES = [
  "arbitrary-color",
  "color-literal",
  "css-literal",
  "dark-variant",
  "fixed-shade",
  "inline-style-color",
  "numbered-primary",
  "raw-source",
  "raw-white-black",
  "unmapped-hue",
  "unmapped-shade",
];
const SCRIPT_PATH = fileURLToPath(import.meta.url);
const SELECTOR_ARGUMENT_PATTERN = /\b(?:querySelector(?:All)?|closest|matches)\(\s*(["'`])[^"'`]*\1/gu;
const SKIPPED_ATTRIBUTE_PATTERN = /(?<![\w-])(?:hx-[\w:-]+|href)\s*=\s*(?:"[^"]*"|'[^']*')/gu;
const STATUS_HUES = ["amber", "emerald", "green", "orange", "red", "yellow"];
const STATUS_SHADES = [50, 100, 200, 700, 800, 900, 950];
const STONE_SHADES = [50, 100, 200, 300, 400, 500, 600, 700, 800, 900];
const STYLE_ATTRIBUTE_PATTERN = /(?<![\w-])style\s*=\s*(?:"([^"]*)"|'([^']*)')/gu;
const TOKEN_DELIMITER_PATTERN = /\s+|["'`]|\{[{%#][-+~]?|[-+~]?[}%#]\}|\$\{|\}/gu;

/**
 * Lints the repository from the command line and prints the report.
 */
const main = () => {
  const args = process.argv.slice(2);
  if (args.length > 0) {
    throw new Error(`unknown argument ${args[0]}; usage: theme-lint.mjs`);
  }
  const { errors, exitCode } = run();
  errors.forEach((line) => console.error(line));
  process.exitCode = exitCode;
};

/**
 * Lints the repository and returns the report lines and exit code.
 * @param {object} [options] - Run options.
 * @param {string} [options.root] - Repository root.
 * @returns {{errors: string[], exitCode: number}} Report lines and status.
 */
export const run = ({ root = REPO_DIR } = {}) => {
  // Scan every input file
  const inputs = listInputs(root);
  const constants = readLightConstants(inputs.find(({ path }) => path === CSS_PATH).text);
  const findings = [];
  const regionErrors = [];
  for (const { path, text } of inputs) {
    if (path === CSS_PATH) {
      const scan = scanStylesheet(path, text);
      findings.push(...scan.findings);
      regionErrors.push(...scan.regionErrors);
    } else {
      findings.push(...scanMarkup(path, text, constants).findings);
    }
  }

  // Apply the allowlist
  const allowlist = loadAllowlist(root);
  const { errors: staleErrors, unallowed } = applyAllowlist(findings, allowlist.entries);

  // Report findings, allowlist errors and marker errors
  const errors = [...unallowed, ...allowlist.errors, ...staleErrors, ...regionErrors].map(formatFinding);
  return { errors, exitCode: errors.length > 0 ? 1 : 0 };
};

/**
 * Matches findings against allowlist entries in file order.
 * @param {object[]} findings - Findings with `path`, `line`, `rule` and `match`.
 * @param {object[]} entries - Valid allowlist entries.
 * @returns {{errors: object[], unallowed: object[]}} Stale entry errors and the findings left
 * without an entry.
 */
export const applyAllowlist = (findings, entries) => {
  const sorted = findings.toSorted(compareFindings);
  const assigned = new Set();
  const errors = [];
  const overflow = new Map();

  for (const entry of entries) {
    const pattern = matchPattern(entry.match);
    const matching = sorted.filter(
      (finding) =>
        !assigned.has(finding) &&
        finding.path === entry.file &&
        finding.rule === entry.rule &&
        pattern.test(finding.match),
    );
    matching.slice(0, entry.count).forEach((finding) => assigned.add(finding));
    matching.slice(entry.count).forEach((finding) => overflow.set(finding, entry));
    if (matching.length < entry.count) {
      errors.push({
        line: entry.line,
        match: entry.match,
        message: `stale allowlist entry for ${entry.file} ${entry.rule} "${entry.match}": count ${entry.count}, found ${matching.length}`,
        path: ALLOWLIST_PATH,
        rule: "allowlist",
      });
    }
  }

  const unallowed = sorted
    .filter((finding) => !assigned.has(finding))
    .map((finding) =>
      overflow.has(finding)
        ? {
            ...finding,
            message: `${finding.message} (exceeds allowlist count ${overflow.get(finding).count} for "${overflow.get(finding).match}")`,
          }
        : finding,
    );
  return { errors, unallowed };
};

/**
 * Parses allowlist JSON and validates every entry.
 * @param {string} text - Allowlist file text.
 * @returns {{entries: object[], errors: object[]}} Valid entries with their line, and malformed
 * entry errors.
 */
export const parseAllowlist = (text) => {
  const malformed = (line, message) => ({
    line,
    match: "",
    message: `malformed allowlist: ${message}`,
    path: ALLOWLIST_PATH,
    rule: "allowlist",
  });
  let data;
  try {
    data = JSON.parse(text);
  } catch (error) {
    return { entries: [], errors: [malformed(1, error.message)] };
  }
  if (!Array.isArray(data)) {
    return { entries: [], errors: [malformed(1, "expected a JSON array")] };
  }

  const entryLines = topLevelObjectLines(text);
  const entries = [];
  const errors = [];
  const seen = new Set();
  data.forEach((entry, index) => {
    const line = entryLines[index] ?? 1;
    if (entry === null || typeof entry !== "object" || Array.isArray(entry)) {
      errors.push(malformed(line, `entry ${index + 1} is not an object`));
      return;
    }
    const problems = [
      ...Object.keys(entry)
        .filter((key) => !ALLOWLIST_FIELDS.includes(key))
        .map((key) => `unknown field "${key}"`),
      ...["file", "match", "reason", "rule"]
        .filter((key) => typeof entry[key] !== "string" || entry[key].trim() === "")
        .map((key) => `missing ${key}`),
    ];
    if (!Number.isInteger(entry.count) || entry.count < 1) {
      problems.push("count must be a positive integer");
    }
    if (typeof entry.rule === "string" && entry.rule !== "" && !RULES.includes(entry.rule)) {
      problems.push(`unknown rule "${entry.rule}"`);
    }
    const key = `${entry.file}\u0000${entry.rule}\u0000${entry.match}`;
    if (problems.length === 0 && seen.has(key)) {
      problems.push("duplicate file, rule and match");
    }
    seen.add(key);
    if (problems.length > 0) {
      errors.push(malformed(line, `entry ${index + 1}: ${problems.join(", ")}`));
      return;
    }
    entries.push({ ...entry, line });
  });
  return { entries, errors };
};

/**
 * Splits a class token into its variant chain and utility, stripping `!` and `/<opacity>`.
 * @param {string} token - Class token.
 * @returns {{raw: string, utility: string, variants: string[]}} Utility without modifiers, the
 * utility as written, and the variants.
 */
export const parseClassToken = (token) => {
  let depth = 0;
  let lastColon = -1;
  for (let index = 0; index < token.length; index += 1) {
    const char = token[index];
    if (char === "[" || char === "(") {
      depth += 1;
    } else if ((char === "]" || char === ")") && depth > 0) {
      depth -= 1;
    } else if (char === ":" && depth === 0) {
      lastColon = index;
    }
  }
  const variants = lastColon < 0 ? [] : splitTopLevel(token.slice(0, lastColon), ":");
  const raw = token.slice(lastColon + 1);
  let utility = raw.replace(/^!+|!+$/gu, "");
  const slash = lastTopLevelIndex(utility, "/");
  if (slash > 0) {
    utility = utility.slice(0, slash);
  }
  return { raw, utility: utility.replace(/^!+|!+$/gu, ""), variants };
};

/**
 * Finds the token regions of a stylesheet.
 * @param {string} text - Stylesheet text.
 * @param {string} [path] - Path used in errors.
 * @returns {{errors: object[], regions: {end: number, start: number}[]}} Regions as offsets and
 * `token-region` marker errors.
 */
export const parseTokenRegions = (text, path = CSS_PATH) => {
  const starts = lineStarts(text);
  const errors = [];
  const regions = [];
  let open = null;
  const error = (index, message) =>
    errors.push({ line: lineOf(starts, index), message, path, rule: "token-region" });

  for (const match of text.matchAll(MARKER_PATTERN)) {
    const body = match[1].trim();
    const [kind] = body.split(/\s+/u);
    const reason = body.slice(kind.length).trim();
    if (kind === "tokens-start") {
      if (!reason) {
        error(match.index, "tokens-start marker needs a reason");
      }
      if (open) {
        error(match.index, "token regions do not nest");
        continue;
      }
      open = match;
    } else if (kind === "tokens-end") {
      if (reason) {
        error(match.index, "tokens-end marker takes no text");
      }
      if (!open) {
        error(match.index, "unmatched tokens-end marker");
        continue;
      }
      regions.push({ end: match.index + match[0].length, start: open.index });
      open = null;
    } else {
      error(match.index, `unknown theme-lint marker "${body}"`);
    }
  }
  if (open) {
    error(open.index, "unmatched tokens-start marker");
  }
  return { errors, regions };
};

/**
 * Scans a template or JS file.
 * @param {string} path - Repository-relative path.
 * @param {string} text - File text.
 * @param {Set<string>} [constants] - Shades with a light constant, for example `stone-200`.
 * @returns {{findings: object[]}} Findings.
 */
export const scanMarkup = (path, text, constants = new Set()) => {
  const starts = lineStarts(text);
  const findings = [];
  const add = (rule, index, match, message) =>
    findings.push({ index, line: lineOf(starts, index), match, message, path, rule });
  const tokens = tokenize(text);

  // Class tokens
  for (const { index, token } of tokens) {
    checkClassToken(token, constants).forEach(({ message, rule }) => add(rule, index, token, message));
  }

  // Custom property reads and quoted names
  for (const read of findReads(text, true)) {
    classifyRead(read, constants).forEach(({ message, rule }) => add(rule, read.index, read.name, message));
  }

  // Color literals, skipping ID references
  const skipped = [
    ...[...text.matchAll(SKIPPED_ATTRIBUTE_PATTERN)].map((match) => [
      match.index,
      match.index + match[0].length,
    ]),
    ...[...text.matchAll(SELECTOR_ARGUMENT_PATTERN)].map((match) => [
      match.index,
      match.index + match[0].length,
    ]),
    ...tokens.flatMap(({ index, token }) =>
      bracketSpans(token).map(([start, end]) => [index + start, index + end]),
    ),
  ];
  for (const literal of findColorLiterals(text)) {
    if (!skipped.some(([start, end]) => literal.index >= start && literal.index < end)) {
      add(
        "color-literal",
        literal.index,
        literal.text,
        `color literal ${literal.text}; read a --color-* token`,
      );
    }
  }

  // Inline style colors
  for (const { index, property, value } of findInlineStyles(text)) {
    const color = findStyleColor(value);
    if (color) {
      add(
        "inline-style-color",
        index,
        color,
        `inline ${property} color ${color}; use a token class or var(--color-...)`,
      );
    }
  }

  // Icon masks painted with the scrim shade
  findings.push(...findIconMaskScrims(path, text, tokens, starts));
  return { findings };
};

/**
 * Scans styles.src.css: `@apply` class tokens, selectors and declaration values.
 * @param {string} path - Repository-relative path.
 * @param {string} text - Stylesheet text.
 * @returns {{findings: object[], regionErrors: object[]}} Findings and token region marker
 * errors.
 */
export const scanStylesheet = (path, text) => {
  const { errors: regionErrors, regions } = parseTokenRegions(text, path);
  const starts = lineStarts(text);
  const root = parseCssBlocks(blankComments(text));
  const constants = readLightConstants(text);
  const findings = [];
  const inRegion = (index) => regions.some(({ end, start }) => index >= start && index < end);
  const add = (rule, index, match, message) =>
    findings.push({ index, line: lineOf(starts, index), match, message, path, rule });

  // @apply class tokens
  for (const statement of findStatements(root, "@apply")) {
    for (const { index, token } of tokenize(statement.body)) {
      const offset = statement.bodyStart + index;
      for (const { message, rule } of checkClassToken(token, constants)) {
        if (!(rule === "arbitrary-color" && inRegion(offset))) {
          add(rule, offset, token, message);
        }
      }
    }
  }

  // Numbered primary class selectors
  for (const node of findNodes(root, (item) => item.prelude && !item.prelude.startsWith("@"))) {
    for (const match of node.prelude.matchAll(/\.((?:[\w-]|\\.)*-primary-\d+)(?![\w-])/gu)) {
      add(
        "numbered-primary",
        node.start + match.index,
        match[1],
        `.${match[1]} selects a numbered primary class; match the primary role class too`,
      );
    }
  }

  // Declaration values and @apply bodies: reads and literals
  const sources = [
    ...allDecls(root).map((decl) => ({ start: decl.valueStart, text: decl.value })),
    ...findStatements(root, "@apply").map((item) => ({ start: item.bodyStart, text: item.body })),
  ];
  for (const source of sources) {
    for (const read of findReads(source.text, false)) {
      const offset = source.start + read.index;
      for (const { message, rule } of classifyRead(read, constants)) {
        if (rule === "unmapped-shade" || !inRegion(offset)) {
          add(rule, offset, read.name, message);
        }
      }
    }
  }
  for (const decl of allDecls(root)) {
    for (const literal of [...findColorLiterals(decl.value), ...findColorKeywords(decl.value)]) {
      const offset = decl.valueStart + literal.index;
      if (!inRegion(offset)) {
        add(
          "css-literal",
          offset,
          literal.text,
          `color literal ${literal.text} outside a token region; use var(--color-...)`,
        );
      }
    }
  }
  return { findings, regionErrors };
};

/**
 * Splits text into class tokens: runs without whitespace, quotes, backticks, Askama delimiters
 * (with an optional `-`, `+` or `~` on the inner side) or JS `${` and `}`.
 * @param {string} text - Source text.
 * @returns {{index: number, token: string}[]} Tokens with their offsets.
 */
export const tokenize = (text) => {
  const tokens = [];
  let start = 0;
  for (const match of text.matchAll(TOKEN_DELIMITER_PATTERN)) {
    if (match.index > start) {
      tokens.push({ index: start, token: text.slice(start, match.index) });
    }
    start = match.index + match[0].length;
  }
  if (start < text.length) {
    tokens.push({ index: start, token: text.slice(start) });
  }
  return tokens;
};

/**
 * Lists every declaration below a node.
 * @param {object} node - CSS block node.
 * @returns {object[]} Declarations.
 */
const allDecls = (node) => [...node.decls, ...node.children.flatMap(allDecls)];

/**
 * Replaces CSS comments with spaces, keeping offsets and line breaks.
 * @param {string} text - Stylesheet text.
 * @returns {string} Text without comments.
 */
const blankComments = (text) =>
  text.replace(/\/\*[\s\S]*?\*\//gu, (comment) => comment.replace(/[^\n]/gu, " "));

/**
 * Finds the bracketed spans of a class token.
 * @param {string} token - Class token.
 * @returns {number[][]} `[start, end)` offsets of each top-level `[...]`.
 */
const bracketSpans = (token) => {
  const spans = [];
  let depth = 0;
  let start = 0;
  for (let index = 0; index < token.length; index += 1) {
    if (token[index] === "[") {
      if (depth === 0) {
        start = index;
      }
      depth += 1;
    } else if (token[index] === "]" && depth > 0) {
      depth -= 1;
      if (depth === 0) {
        spans.push([start, index + 1]);
      }
    }
  }
  if (depth > 0) {
    spans.push([start, token.length]);
  }
  return spans;
};

/**
 * Applies the class token rules to one token.
 * @param {string} token - Class token.
 * @param {Set<string>} constants - Shades with a light constant.
 * @returns {{message: string, rule: string}[]} Findings.
 */
const checkClassToken = (token, constants) => {
  const { raw, utility, variants } = parseClassToken(token);
  const findings = [];
  const add = (rule, message) => findings.push({ message, rule });

  if (RAW_WHITE_BLACK_PATTERN.test(utility)) {
    add(
      "raw-white-black",
      `${token}: use a semantic token (surface, raised, plate, on-fill, on-primary) or stone-900 text`,
    );
  }
  const hue = BANNED_HUE_UTILITY_PATTERN.exec(utility);
  if (hue) {
    add("unmapped-hue", `${token}: ${hue[1]} is not in the palette; use the nearest stone shade`);
  }
  const stone950 = /^([a-z][a-z-]*)-stone-950$/u.exec(utility);
  if (stone950 && stone950[1] !== "bg") {
    add("fixed-shade", `${token}: stone-950 is a fixed scrim shade; use stone-900 for foregrounds`);
  }
  if (/^[a-z][a-z-]*-primary-\d+$/u.test(utility)) {
    add(
      "numbered-primary",
      `${token}: use a primary role (fill, tint, fg, edge or halo in the @theme static block)`,
    );
  }
  if (ARBITRARY_HEX_PATTERN.test(raw) || ARBITRARY_FUNCTION_PATTERN.test(raw) || hasShadowColor(raw)) {
    add("arbitrary-color", `${token}: arbitrary color; use a --color-* token`);
  }
  if (variants.includes("dark") && utility !== "") {
    add("dark-variant", `${token}: dark class variants need an allowlist entry; prefer tokens`);
  }
  const shade = PALETTE_SHADE_UTILITY_PATTERN.exec(utility)?.[1];
  if (shade && isRemappableShade(shade) && !constants.has(shade)) {
    add("unmapped-shade", `${token}: ${unmappedShadeMessage(shade)}`);
  }
  return findings;
};

/**
 * Classifies one custom property read.
 * @param {{form: string, name: string}} read - Read form (`var`, `paren` or `quote`) and name.
 * @param {Set<string>} constants - Shades with a light constant.
 * @returns {{message: string, rule: string}[]} Findings.
 */
const classifyRead = ({ form, name }, constants) => {
  const findings = [];
  const add = (rule, message) => findings.push({ message, rule });
  if (/^--color-(?:white|black)$/u.test(name)) {
    add("raw-white-black", `reads ${name}; use a semantic token`);
  }
  const hue = BANNED_HUE_READ_PATTERN.exec(name);
  if (hue) {
    add("unmapped-hue", `reads ${name}; ${hue[1]} is not in the palette`);
  }
  if (name === "--color-stone-950") {
    add("fixed-shade", `reads ${name} outside a token region; stone-950 is a fixed scrim shade`);
  }
  if (/^--color-primary-\d+$/u.test(name)) {
    add("numbered-primary", `reads ${name}; use a primary role`);
  }
  if (form !== "quote" && /^--ocg-(?:primary-light|primary-dark|light)-/u.test(name)) {
    add("raw-source", `reads color source ${name} outside a token region; read a --color-* token`);
  }
  const shade = PALETTE_SHADE_READ_PATTERN.exec(name)?.[1];
  if (shade && isRemappableShade(shade) && !constants.has(shade)) {
    add("unmapped-shade", `reads ${name}; ${unmappedShadeMessage(shade)}`);
  }
  return findings;
};

/**
 * Orders findings by path, line and offset.
 * @param {object} first - Finding.
 * @param {object} second - Finding.
 * @returns {number} Sort order.
 */
const compareFindings = (first, second) =>
  first.path.localeCompare(second.path) ||
  first.line - second.line ||
  (first.index ?? 0) - (second.index ?? 0);

/**
 * Finds the color keywords `white` and `black` used as values.
 * @param {string} text - Declaration value.
 * @returns {{index: number, text: string}[]} Keywords with their offsets.
 */
const findColorKeywords = (text) =>
  [...text.matchAll(COLOR_KEYWORD_PATTERN)].map((match) => ({ index: match.index, text: match[0] }));

/**
 * Finds hex colors and color functions.
 * @param {string} text - Source text.
 * @returns {{index: number, text: string}[]} Literals with their offsets.
 */
const findColorLiterals = (text) => [
  ...[...text.matchAll(HEX_PATTERN)].map((match) => ({ index: match.index, text: match[0] })),
  ...[...text.matchAll(COLOR_FUNCTION_PATTERN)].map((match) => ({
    index: match.index,
    text: text.slice(match.index, matchingParen(text, match.index + match[0].length - 1) + 1),
  })),
];

/**
 * Finds `bg-stone-950` in the same class string as `svg-icon`.
 * @param {string} path - Repository-relative path.
 * @param {string} text - File text.
 * @param {{index: number, token: string}[]} tokens - Class tokens of the file.
 * @param {number[]} starts - Line start offsets.
 * @returns {object[]} Findings.
 */
const findIconMaskScrims = (path, text, tokens, starts) => {
  const masked = maskExpressions(text);
  return tokens
    .filter(({ token }) => parseClassToken(token).utility === "bg-stone-950")
    .filter(({ index, token }) => {
      const span = quotedSpan(masked, index, index + token.length);
      return span && /(?:^|[\s"'`])svg-icon(?=$|[\s"'`])/u.test(masked.slice(span[0], span[1]));
    })
    .map(({ index, token }) => ({
      index,
      line: lineOf(starts, index),
      match: token,
      message: `${token} on an svg-icon mask is a mark, not a scrim; use stone-900`,
      path,
      rule: "fixed-shade",
    }));
};

/**
 * Finds color properties set inline: `style=` attributes and JS `.style.<prop> =`,
 * `.style.setProperty()` and `cssText` assignments.
 * @param {string} text - File text.
 * @returns {{index: number, property: string, value: string}[]} Inline declarations.
 */
const findInlineStyles = (text) => {
  const styles = [];
  const addDeclarations = (body, start) => {
    let offset = 0;
    for (const part of body.split(";")) {
      const colon = part.indexOf(":");
      if (colon > 0) {
        styles.push({
          index: start + offset,
          property: part.slice(0, colon).trim().toLowerCase(),
          value: part.slice(colon + 1),
        });
      }
      offset += part.length + 1;
    }
  };
  for (const match of text.matchAll(STYLE_ATTRIBUTE_PATTERN)) {
    addDeclarations(match[1] ?? match[2], match.index);
  }
  for (const match of text.matchAll(/\.style\.([a-zA-Z]+)\s*=(?!=)([^;\n]*)/gu)) {
    styles.push({ index: match.index, property: kebabCase(match[1]), value: match[2] });
  }
  for (const match of text.matchAll(/\.style\.setProperty\(\s*(["'`])([\w-]+)\1\s*,([^\n]*)/gu)) {
    styles.push({ index: match.index, property: match[2], value: match[3] });
  }
  for (const match of text.matchAll(/\.cssText\s*\+?=\s*(["'`])([^\n]*?)\1/gu)) {
    addDeclarations(match[2], match.index);
  }
  return styles.filter(({ property }) => isColorProperty(property));
};

/**
 * Lists every block below a node that matches a predicate.
 * @param {object} node - CSS block node.
 * @param {(node: object) => boolean} predicate - Filter.
 * @returns {object[]} Matching nodes in document order.
 */
const findNodes = (node, predicate) =>
  node.children.flatMap((child) => [...(predicate(child) ? [child] : []), ...findNodes(child, predicate)]);

/**
 * Finds custom property reads: `var(--x)`, `-(--x)` and, in markup, quoted `"--x"` names.
 * @param {string} text - Source text.
 * @param {boolean} quoted - Whether quoted names count.
 * @returns {{form: string, index: number, name: string}[]} Reads with their offsets.
 */
const findReads = (text, quoted) =>
  [...text.matchAll(READ_PATTERN)]
    .filter((match) => quoted || !match[2])
    .map((match) => ({
      form: match[2] ? "quote" : match[1] === "var(" ? "var" : "paren",
      index: match.index + match[0].length - match[3].length,
      name: match[3],
    }));

/**
 * Lists the at-rule statements with a given name below a node.
 * @param {object} node - CSS block node.
 * @param {string} name - Statement name, for example `@apply`.
 * @returns {object[]} Statements.
 */
const findStatements = (node, name) => [
  ...node.statements.filter((statement) => statement.name === name),
  ...node.children.flatMap((child) => findStatements(child, name)),
];

/**
 * Finds the first color literal or `white`/`black` keyword in an inline style value; token reads
 * and template expressions are not colors.
 * @param {string} value - Inline style value.
 * @returns {string|null} The color, or null.
 */
const findStyleColor = (value) => {
  const masked = maskExpressions(value);
  const literal = findColorLiterals(masked)[0] ?? findColorKeywords(masked)[0];
  return literal ? literal.text : null;
};

/**
 * Formats a finding or error as `path:line: rule: message`.
 * @param {object} finding - Finding.
 * @returns {string} Report line.
 */
const formatFinding = ({ line, message, path, rule }) => `${path}:${line}: ${rule}: ${message}`;

/**
 * Tells whether an arbitrary shadow utility holds a color.
 * @param {string} utility - Utility as written.
 * @returns {boolean} True when a color sits inside `shadow-[...]`.
 */
const hasShadowColor = (utility) => {
  const match = /(?:^|-)shadow-\[(.*)\]/u.exec(utility);
  return Boolean(
    match &&
    (/#[0-9a-fA-F]{3,8}(?![0-9a-zA-Z])/u.test(match[1]) ||
      /(?:rgba?|hsla?|oklch|oklab|color-mix)\(/u.test(match[1]) ||
      /(?<![a-zA-Z-])(?:white|black)(?![a-zA-Z-])/u.test(match[1])),
  );
};

/**
 * Tells whether an inline style property paints a color.
 * @param {string} property - Kebab-case property name.
 * @returns {boolean} True for color properties and custom properties.
 */
const isColorProperty = (property) =>
  property.startsWith("--") ||
  property.includes("color") ||
  /^(?:background(?:-image)?|border(?:-(?:top|right|bottom|left|block|inline)(?:-(?:start|end))?)?|outline|fill|stroke|box-shadow|text-shadow|text-decoration)$/u.test(
    property,
  );

/**
 * Tells whether a palette shade is remapped: stone 50-900, or a status shade in the 50-200 or
 * 700-950 bands.
 * @param {string} name - Shade name, for example `stone-200`.
 * @returns {boolean} True for remapped shades.
 */
const isRemappableShade = (name) => {
  const [hue, shade] = name.split("-");
  return hue === "stone"
    ? STONE_SHADES.includes(Number(shade))
    : STATUS_HUES.includes(hue) && STATUS_SHADES.includes(Number(shade));
};

/**
 * Converts a camelCase style property to kebab case.
 * @param {string} name - Property name.
 * @returns {string} Kebab-case name.
 */
const kebabCase = (name) => name.replace(/[A-Z]/gu, (char) => `-${char.toLowerCase()}`);

/**
 * Finds the last occurrence of a character outside `[...]` and `(...)`.
 * @param {string} text - Text.
 * @param {string} char - Character.
 * @returns {number} Index, or -1.
 */
const lastTopLevelIndex = (text, char) => {
  let depth = 0;
  let found = -1;
  for (let index = 0; index < text.length; index += 1) {
    if (text[index] === "[" || text[index] === "(") {
      depth += 1;
    } else if ((text[index] === "]" || text[index] === ")") && depth > 0) {
      depth -= 1;
    } else if (text[index] === char && depth === 0) {
      found = index;
    }
  }
  return found;
};

/**
 * Returns the 1-based line of an offset.
 * @param {number[]} starts - Line start offsets.
 * @param {number} index - Offset.
 * @returns {number} Line number.
 */
const lineOf = (starts, index) => {
  let low = 0;
  let high = starts.length - 1;
  while (low < high) {
    const middle = Math.ceil((low + high) / 2);
    if (starts[middle] <= index) {
      low = middle;
    } else {
      high = middle - 1;
    }
  }
  return low + 1;
};

/**
 * Lists the offsets where each line starts.
 * @param {string} text - Text.
 * @returns {number[]} Line start offsets.
 */
const lineStarts = (text) => {
  const starts = [0];
  for (let index = text.indexOf("\n"); index >= 0; index = text.indexOf("\n", index + 1)) {
    starts.push(index + 1);
  }
  return starts;
};

/**
 * Lists the lint inputs: templates (emails excluded), static JS and styles.src.css.
 * @param {string} root - Repository root.
 * @returns {{path: string, text: string}[]} Inputs sorted by path.
 */
const listInputs = (root) => {
  const list = (folder, accept) =>
    readdirSync(join(root, folder), { recursive: true })
      .map((entry) => String(entry).split(sep).join("/"))
      .filter(accept)
      .map((entry) => `${folder}/${entry}`);
  const templates = list(
    "ocg-server/templates",
    (entry) =>
      /\.(?:html|js)$/u.test(entry) && !entry.startsWith("notifications/") && entry !== "macros/email.html",
  );
  const scripts = list("ocg-server/static/js", (entry) => entry.endsWith(".js"));
  return [...templates, ...scripts, CSS_PATH]
    .toSorted()
    .map((path) => ({ path, text: readFileSync(join(root, path), "utf8") }));
};

/**
 * Loads and validates the allowlist.
 * @param {string} root - Repository root.
 * @returns {{entries: object[], errors: object[]}} Entries and malformed entry errors.
 */
const loadAllowlist = (root) => {
  const text = readOptional(join(root, ALLOWLIST_PATH));
  return text === null ? { entries: [], errors: [] } : parseAllowlist(text);
};

/**
 * Masks Askama expressions and JS interpolations with spaces, keeping offsets.
 * @param {string} text - Source text.
 * @returns {string} Masked text.
 */
const maskExpressions = (text) =>
  text.replace(/\{\{[\s\S]*?\}\}|\{%[\s\S]*?%\}|\{#[\s\S]*?#\}|\$\{[^}]*\}/gu, (expression) =>
    expression.replace(/[^\n]/gu, " "),
  );

/**
 * Builds the matcher of an allowlist `match`, where `<N>` stands for a shade number.
 * @param {string} match - Allowlist match.
 * @returns {RegExp} Anchored pattern.
 */
const matchPattern = (match) =>
  new RegExp(
    `^${match
      .split("<N>")
      .map((part) => part.replace(/[.*+?^${}()|[\]\\]/gu, "\\$&"))
      .join("\\d+")}$`,
    "u",
  );

/**
 * Finds the parenthesis that closes the one at `open`.
 * @param {string} text - Text.
 * @param {number} open - Offset of `(`.
 * @returns {number} Offset of the matching `)`, or the end of the line.
 */
const matchingParen = (text, open) => {
  let depth = 0;
  for (let index = open; index < text.length; index += 1) {
    if (text[index] === "(") {
      depth += 1;
    } else if (text[index] === ")") {
      depth -= 1;
      if (depth === 0) {
        return index;
      }
    } else if (text[index] === "\n") {
      return index - 1;
    }
  }
  return text.length - 1;
};

/**
 * Collapses the whitespace of a block prelude.
 * @param {string} prelude - Selector or at-rule prelude.
 * @returns {string} Normalised prelude.
 */
const normalizePrelude = (prelude) => prelude.replace(/\s+/gu, " ").trim();

/**
 * Parses comment-free CSS into nested blocks with declarations and at-rule statements.
 * @param {string} text - Stylesheet text with comments blanked.
 * @returns {object} Root node.
 */
const parseCssBlocks = (text) => {
  const makeNode = (parent, prelude, start) => ({
    children: [],
    decls: [],
    parent,
    prelude,
    start,
    statements: [],
  });
  const root = makeNode(null, "", 0);
  let node = root;
  let segment = 0;
  let depth = 0;
  let quote = null;

  const flush = (end) => {
    const raw = text.slice(segment, end);
    const start = segment + (raw.length - raw.trimStart().length);
    const body = raw.trim();
    if (!body) {
      return;
    }
    if (body.startsWith("@")) {
      const name = /^@[\w-]+/u.exec(body)[0];
      const rest = body.slice(name.length);
      const bodyStart = start + name.length + (rest.length - rest.trimStart().length);
      node.statements.push({ body: rest.trim(), bodyStart, name });
      return;
    }
    const colon = body.indexOf(":");
    if (colon < 0) {
      return;
    }
    const rawValue = body.slice(colon + 1);
    node.decls.push({
      value: rawValue.trim(),
      valueStart: start + colon + 1 + (rawValue.length - rawValue.trimStart().length),
    });
  };

  for (let index = 0; index < text.length; index += 1) {
    const char = text[index];
    if (quote) {
      if (char === "\\") {
        index += 1;
      } else if (char === quote) {
        quote = null;
      }
    } else if (char === '"' || char === "'") {
      quote = char;
    } else if (char === "(") {
      depth += 1;
    } else if (char === ")") {
      depth = Math.max(0, depth - 1);
    } else if (depth > 0) {
      continue;
    } else if (char === "{") {
      const raw = text.slice(segment, index);
      const child = makeNode(node, normalizePrelude(raw), segment + (raw.length - raw.trimStart().length));
      node.children.push(child);
      node = child;
      segment = index + 1;
    } else if (char === ";") {
      flush(index);
      segment = index + 1;
    } else if (char === "}") {
      flush(index);
      node = node.parent ?? root;
      segment = index + 1;
    }
  }
  return root;
};

/**
 * Finds the quoted string around a span: the nearest quote before it and the next same quote
 * after it.
 * @param {string} text - Masked source text.
 * @param {number} start - Span start.
 * @param {number} end - Span end.
 * @returns {number[]|null} `[start, end)` of the string body, or null.
 */
const quotedSpan = (text, start, end) => {
  let open = start - 1;
  while (open >= 0 && !`"'\``.includes(text[open])) {
    open -= 1;
  }
  if (open < 0) {
    return null;
  }
  const close = text.indexOf(text[open], end);
  return close < 0 ? null : [open + 1, close];
};

/**
 * Reads the shades that have an `--ocg-light-<hue>-<shade>` constant declared in styles.src.css.
 * @param {string} text - Stylesheet text.
 * @returns {Set<string>} Shade names, for example `stone-200`.
 */
const readLightConstants = (text) =>
  new Set([...blankComments(text).matchAll(LIGHT_CONSTANT_PATTERN)].map((match) => match[1]));

/**
 * Reads a file, or returns null when it does not exist.
 * @param {string} path - Absolute path.
 * @returns {string|null} File text.
 */
const readOptional = (path) => {
  try {
    return readFileSync(path, "utf8");
  } catch (error) {
    if (error.code === "ENOENT") {
      return null;
    }
    throw error;
  }
};

/**
 * Splits text on a separator outside `[...]` and `(...)`.
 * @param {string} text - Text.
 * @param {string} separator - Separator character.
 * @returns {string[]} Parts.
 */
const splitTopLevel = (text, separator) => {
  const parts = [];
  let depth = 0;
  let start = 0;
  for (let index = 0; index < text.length; index += 1) {
    if (text[index] === "[" || text[index] === "(") {
      depth += 1;
    } else if ((text[index] === "]" || text[index] === ")") && depth > 0) {
      depth -= 1;
    } else if (text[index] === separator && depth === 0) {
      parts.push(text.slice(start, index));
      start = index + 1;
    }
  }
  parts.push(text.slice(start));
  return parts;
};

/**
 * Finds the line of each top-level object in a JSON array.
 * @param {string} text - JSON text.
 * @returns {number[]} 1-based lines, one per array element object.
 */
const topLevelObjectLines = (text) => {
  const starts = lineStarts(text);
  const lines = [];
  let depth = 0;
  let inString = false;
  for (let index = 0; index < text.length; index += 1) {
    const char = text[index];
    if (inString) {
      if (char === "\\") {
        index += 1;
      } else if (char === '"') {
        inString = false;
      }
    } else if (char === '"') {
      inString = true;
    } else if (char === "[" || char === "{") {
      if (depth === 1) {
        lines.push(lineOf(starts, index));
      }
      depth += 1;
    } else if (char === "]" || char === "}") {
      depth -= 1;
    }
  }
  return lines;
};

/**
 * Describes a remapped shade without a light constant.
 * @param {string} shade - Shade name, for example `green-700`.
 * @returns {string} Message.
 */
const unmappedShadeMessage = (shade) =>
  `${shade} has no --ocg-light-${shade} constant, so it stays light in dark`;

if (process.argv[1] && resolve(process.argv[1]) === SCRIPT_PATH) {
  try {
    main();
  } catch (error) {
    console.error(`error: ${error.message}`);
    process.exitCode = 1;
  }
}
