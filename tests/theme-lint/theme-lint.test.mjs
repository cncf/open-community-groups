import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { after, describe, test } from "node:test";
import { fileURLToPath } from "node:url";

import {
  applyAllowlist,
  parseAllowlist,
  parseClassToken,
  parseTokenRegions,
  run,
  scanMarkup,
  scanStylesheet,
  tokenize,
} from "./theme-lint.mjs";

const ALLOWLIST_PATH = "tests/theme-lint/theme-lint-allowlist.json";
const CLEAN_CSS = `@import "tailwindcss";
/* theme-lint: tokens-start color tokens with their light values */
@theme static {
  --color-surface: #fff;
}
/* theme-lint: tokens-end */
`;
const CSS_PATH = "ocg-server/static/css/styles.src.css";
const SCRIPT_PATH = fileURLToPath(new URL("./theme-lint.mjs", import.meta.url));
const TEMP_DIRS = [];

/**
 * Lists the matches a rule reports.
 * @param {{findings: object[]}} scan - Scan result.
 * @param {string} rule - Rule name.
 * @returns {string[]} Matches.
 */
const matchesOf = (scan, rule) =>
  scan.findings.filter((finding) => finding.rule === rule).map(({ match }) => match);

/**
 * Lists the class tokens of a text.
 * @param {string} text - Source text.
 * @returns {string[]} Tokens.
 */
const tokensOf = (text) => tokenize(text).map(({ token }) => token);

/**
 * Writes a repository fixture in a temp dir.
 * @param {object} files - File texts keyed by repository-relative path.
 * @returns {string} Repository root.
 */
const writeRepo = (files) => {
  const root = mkdtempSync(join(tmpdir(), "theme-lint-"));
  TEMP_DIRS.push(root);
  const all = {
    [ALLOWLIST_PATH]: "[]",
    "ocg-server/static/js/.keep.js": "",
    "ocg-server/templates/.keep.html": "",
    [CSS_PATH]: CLEAN_CSS,
    ...files,
  };
  for (const [path, text] of Object.entries(all)) {
    mkdirSync(dirname(join(root, path)), { recursive: true });
    writeFileSync(join(root, path), text);
  }
  return root;
};

after(() => {
  // Remove the repository fixtures
  for (const root of TEMP_DIRS) {
    rmSync(root, { force: true, recursive: true });
  }
});

describe("tokenizer", () => {
  test("splits on whitespace, quotes, Askama delimiters and JS interpolation", () => {
    assert.deepEqual(tokensOf("{% if a %}bg-white{% else %}bg-stone-100{% endif %}"), [
      "if",
      "a",
      "bg-white",
      "else",
      "bg-stone-100",
      "endif",
    ]);
    assert.deepEqual(tokensOf("{%- if b -%}x{{~ c ~}}y{#+ d +#}"), ["if", "b", "x", "c", "y", "d"]);
    assert.deepEqual(tokensOf("`a ${b}c`"), ["a", "b", "c"]);
  });

  test("reads the variant chain up to the last colon outside brackets", () => {
    assert.deepEqual(parseClassToken("phone:[&>#header]:bg-white"), {
      raw: "bg-white",
      utility: "bg-white",
      variants: ["phone", "[&>#header]"],
    });
    assert.equal(parseClassToken("has-[#user-dropdown:not(.hidden)]:z-[1100]").utility, "z-[1100]");
    assert.equal(parseClassToken("hover:bg-white/85").utility, "bg-white");
    assert.equal(parseClassToken("!bg-white").utility, "bg-white");
    assert.equal(parseClassToken("bg-white/50!").utility, "bg-white");
  });

  test("hits raw white in every class token form", () => {
    for (const fixture of [
      'class="phone:[&>#header]:bg-white"',
      'class="hover:bg-white/85"',
      'class="!bg-white"',
      "{% if b %} phone:bg-white{% endif %}",
    ]) {
      assert.equal(matchesOf(scanMarkup("a.html", fixture), "raw-white-black").length, 1, fixture);
    }
    const scan = scanMarkup("a.html", "{% if a %}bg-white{% else %}bg-stone-100{% endif %}");
    assert.deepEqual(matchesOf(scan, "raw-white-black"), ["bg-white"]);
  });

  test("hits a class wrapped by an Askama condition on a quoted value", () => {
    const scan = scanMarkup("a.html", '{% if dot == "danger" %}bg-primary-800{% endif %}');
    assert.deepEqual(matchesOf(scan, "numbered-primary"), ["bg-primary-800"]);
  });

  test("does not hit ID selectors, hx-* values or property names", () => {
    const fixture = [
      '<div class="has-[#user-dropdown:not(.hidden)]:z-[1100]"></div>',
      '<div class="group-has-[#pending-changes-alert:not(.hidden)]/event-page:row-start-3"></div>',
      '<button hx-disabled-elt="#add-event-button, #cancel-button"></button>',
      '<p style="white-space: normal"></p>',
    ].join("\n");
    assert.deepEqual(scanMarkup("a.html", fixture).findings, []);
    assert.deepEqual(scanStylesheet(CSS_PATH, ".a { white-space: normal; }").findings, []);
  });
});

describe("rules", () => {
  test("raw-white-black", () => {
    assert.deepEqual(
      matchesOf(scanMarkup("a.js", 'el.classList.add("text-white", "border-t-black");'), "raw-white-black"),
      ["text-white", "border-t-black"],
    );
    assert.deepEqual(
      matchesOf(scanMarkup("a.js", 'styles.getPropertyValue("--color-white");'), "raw-white-black"),
      ["--color-white"],
    );
    assert.deepEqual(
      matchesOf(scanStylesheet(CSS_PATH, ".a { --strip-surface: var(--color-white); }"), "raw-white-black"),
      ["--color-white"],
    );
    assert.deepEqual(
      matchesOf(scanStylesheet(CSS_PATH, ".a { @apply bg-white text-stone-900; }"), "raw-white-black"),
      ["bg-white"],
    );
    assert.deepEqual(
      matchesOf(scanMarkup("a.html", '<div class="bg-surface text-on-fill white"></div>'), "raw-white-black"),
      [],
    );
  });

  test("unmapped-hue", () => {
    assert.deepEqual(
      matchesOf(
        scanMarkup("a.html", '<hr class="bg-neutral-200"><svg-spinner class="text-gray-500">'),
        "unmapped-hue",
      ),
      ["bg-neutral-200", "text-gray-500"],
    );
    assert.deepEqual(
      matchesOf(scanStylesheet(CSS_PATH, ".a { color: var(--color-slate-200); }"), "unmapped-hue"),
      ["--color-slate-200"],
    );
    assert.deepEqual(matchesOf(scanMarkup("a.html", '<hr class="bg-stone-200">'), "unmapped-hue"), []);
  });

  test("unmapped-shade", () => {
    const constants = new Set(["green-800", "stone-200"]);
    assert.deepEqual(
      matchesOf(
        scanMarkup(
          "a.html",
          '<p class="text-green-700 bg-yellow-700/40 hover:border-orange-800 bg-green-800 bg-stone-200 text-stone-950 bg-green-500">',
          constants,
        ),
        "unmapped-shade",
      ),
      ["text-green-700", "bg-yellow-700/40", "hover:border-orange-800"],
    );
    assert.deepEqual(
      matchesOf(
        scanMarkup(
          "a.js",
          'el.style.setProperty("--x", "var(--color-emerald-100)"); readChartColor(styles, "--color-red-700");',
          constants,
        ),
        "unmapped-shade",
      ),
      ["--color-emerald-100", "--color-red-700"],
    );
    const css = `/* theme-lint: tokens-start light palette constants */
:root { --ocg-light-green-800: #166534; }
/* theme-lint: tokens-end */
.a { @apply text-green-700 text-green-800; color: var(--color-amber-950); border-color: var(--color-green-800); }`;
    assert.deepEqual(matchesOf(scanStylesheet(CSS_PATH, css), "unmapped-shade"), [
      "text-green-700",
      "--color-amber-950",
    ]);
  });

  test("unmapped-shade is checked inside a token region", () => {
    const region = `.a {
  /* theme-lint: tokens-start shadow, mask or transparent edge, kept for light parity */
  @apply text-green-700;
  color: var(--color-green-700);
  /* theme-lint: tokens-end */
}`;
    assert.deepEqual(
      scanStylesheet(CSS_PATH, region).findings.map(({ match, rule }) => `${rule}: ${match}`),
      ["unmapped-shade: text-green-700", "unmapped-shade: --color-green-700"],
    );
  });

  test("fixed-shade", () => {
    assert.deepEqual(matchesOf(scanMarkup("a.html", '<h1 class="text-stone-950">'), "fixed-shade"), [
      "text-stone-950",
    ]);
    assert.deepEqual(
      matchesOf(
        scanMarkup(
          "a.js",
          'const icon = `<div class="svg-icon size-5 bg-stone-950 icon-caret-left"></div>`;',
        ),
        "fixed-shade",
      ),
      ["bg-stone-950"],
    );
    assert.deepEqual(
      matchesOf(
        scanMarkup("a.html", '<div class="svg-icon {% if a == "b" %}size-4{% endif %} bg-stone-950"></div>'),
        "fixed-shade",
      ),
      ["bg-stone-950"],
    );
    assert.deepEqual(
      matchesOf(
        scanMarkup(
          "a.html",
          '<div class="bg-stone-950 opacity-[0.35]"></div><dialog class="backdrop:bg-stone-950/35"></dialog>',
        ),
        "fixed-shade",
      ),
      [],
    );
  });

  test("fixed-shade reads the scrim only inside a token region", () => {
    const scrim = "background: color-mix(in srgb, var(--color-stone-950) 35%, transparent);";
    assert.deepEqual(matchesOf(scanStylesheet(CSS_PATH, `.account-sheet { ${scrim} }`), "fixed-shade"), [
      "--color-stone-950",
    ]);
    const region = `.account-sheet {
  /* theme-lint: tokens-start scrim, fixed in every theme */
  ${scrim}
  /* theme-lint: tokens-end */
}`;
    assert.deepEqual(scanStylesheet(CSS_PATH, region).findings, []);
  });

  test("numbered-primary", () => {
    assert.deepEqual(
      matchesOf(
        scanMarkup("a.html", '<a class="hover:bg-primary-700 focus:ring-primary-300 bg-primary-50/60">'),
        "numbered-primary",
      ),
      ["hover:bg-primary-700", "focus:ring-primary-300", "bg-primary-50/60"],
    );
    assert.deepEqual(
      matchesOf(scanMarkup("a.js", 'readChartColor(styles, "--color-primary-50");'), "numbered-primary"),
      ["--color-primary-50"],
    );
    assert.deepEqual(
      matchesOf(
        scanStylesheet(
          CSS_PATH,
          ".inert-form :is(.border-primary-500, .border-primary-edge) { color: inherit; }",
        ),
        "numbered-primary",
      ),
      ["border-primary-500"],
    );
    assert.deepEqual(
      matchesOf(
        scanStylesheet(CSS_PATH, ".a { @apply bg-primary-500; color: var(--color-primary-500); }"),
        "numbered-primary",
      ),
      ["bg-primary-500", "--color-primary-500"],
    );
    assert.deepEqual(
      matchesOf(
        scanMarkup("a.html", '<a class="bg-primary-fill hover:bg-primary-fill-hover">'),
        "numbered-primary",
      ),
      [],
    );
  });

  test("raw-source", () => {
    assert.deepEqual(
      matchesOf(scanMarkup("a.html", '<a class="outline-(--ocg-primary-light-500)">'), "raw-source"),
      ["--ocg-primary-light-500"],
    );
    assert.deepEqual(
      matchesOf(scanStylesheet(CSS_PATH, ".a { color: var(--ocg-primary-dark-fill); }"), "raw-source"),
      ["--ocg-primary-dark-fill"],
    );
    assert.deepEqual(
      matchesOf(scanStylesheet(CSS_PATH, ".a { --spinner-base: var(--ocg-light-stone-200); }"), "raw-source"),
      ["--ocg-light-stone-200"],
    );
    const region = `/* theme-lint: tokens-start paints on a primary fill in both themes */
.spinner-variant-2 { --spinner-base: var(--ocg-light-stone-200); }
/* theme-lint: tokens-end */`;
    assert.deepEqual(scanStylesheet(CSS_PATH, region).findings, []);
    assert.deepEqual(
      matchesOf(
        scanStylesheet(CSS_PATH, ":root { --ocg-primary-light-500: var(--x); --ocg-docs-top-offset: 1rem; }"),
        "raw-source",
      ),
      [],
    );
  });

  test("arbitrary-color", () => {
    assert.deepEqual(
      matchesOf(
        scanMarkup(
          "a.html",
          '<div class="bg-[#fff] text-[rgb(0_0_0)] shadow-[0_0_28px_rgb(0_0_0_/_0.22)] border-[#abc]/50">',
        ),
        "arbitrary-color",
      ),
      ["bg-[#fff]", "text-[rgb(0_0_0)]", "shadow-[0_0_28px_rgb(0_0_0_/_0.22)]", "border-[#abc]/50"],
    );
    assert.deepEqual(
      matchesOf(
        scanMarkup(
          "a.html",
          '<div class="has-[#pending-changes-alert:not(.hidden)]:mt-2 group-has-[#pending-changes-alert:not(.hidden)]/event-page:row-start-3 bg-(--color-surface) shadow-[0_1px_2px_var(--color-shade)]">',
        ),
        "arbitrary-color",
      ),
      [],
    );
  });

  test("arbitrary-color in @apply is exempt inside a token region", () => {
    const shadow = "@apply shadow-[0_0_20px_-2px_rgba(0,0,0,0.25)]!;";
    assert.equal(
      matchesOf(scanStylesheet(CSS_PATH, `.ocg-swal-popup { ${shadow} }`), "arbitrary-color").length,
      1,
    );
    const region = `.ocg-swal-popup {
  /* theme-lint: tokens-start shadow, mask or transparent edge, kept for light parity */
  ${shadow}
  /* theme-lint: tokens-end */
}`;
    assert.deepEqual(scanStylesheet(CSS_PATH, region).findings, []);
  });

  test("color-literal", () => {
    assert.deepEqual(
      matchesOf(
        scanMarkup("a.html", '<path fill="#e5e7eb"></path><path stroke="rgb(1, 2, 3)"></path>'),
        "color-literal",
      ),
      ["#e5e7eb", "rgb(1, 2, 3)"],
    );
    assert.deepEqual(matchesOf(scanMarkup("a.js", 'const track = "#e5e7eb";'), "color-literal"), ["#e5e7eb"]);
    const ids = [
      '<a href="#fab" hx-target="#bad" hx-disabled-elt="#add-event-button, #cancel-button"></a>',
      '<div class="has-[#fab]:hidden">&#039;</div>',
      'document.querySelector("#bad"); el.closest("#fab");',
      "const id = `#${name}`; const anchor = '/docs#cafe-1';",
    ].join("\n");
    assert.deepEqual(matchesOf(scanMarkup("a.js", ids), "color-literal"), []);
  });

  test("inline-style-color", () => {
    const gradient = 'banner.style.background = "linear-gradient(135deg, #f5f5f4, #e7e5e4)";';
    assert.deepEqual(matchesOf(scanMarkup("a.js", gradient), "inline-style-color"), ["#f5f5f4"]);
    assert.deepEqual(
      matchesOf(scanMarkup("a.js", 'el.style.setProperty("border-color", "white");'), "inline-style-color"),
      ["white"],
    );
    assert.deepEqual(
      matchesOf(scanMarkup("a.js", 'el.style.cssText = "color: #000; width: 1px";'), "inline-style-color"),
      ["#000"],
    );
    assert.deepEqual(matchesOf(scanMarkup("a.html", '<p style="color: rgb(0 0 0)">'), "inline-style-color"), [
      "rgb(0 0 0)",
    ]);
    const tokens = [
      'el.style.background = "var(--color-stone-100)";',
      'el.style.width = "#fff";',
      '<p style="background-color: var(--color-surface); --label-color: {{ color }}; border-color: var(--label-color)">',
    ].join("\n");
    assert.deepEqual(matchesOf(scanMarkup("a.html", tokens), "inline-style-color"), []);
  });

  test("css-literal", () => {
    const css = `.a {
  color: #fff;
  border: 1px solid rgb(209, 213, 219);
  --fc-event-text-color: black;
  mask-image: linear-gradient(to bottom, black, transparent);
}`;
    assert.deepEqual(matchesOf(scanStylesheet(CSS_PATH, css), "css-literal"), [
      "#fff",
      "rgb(209, 213, 219)",
      "black",
      "black",
    ]);
    const clean = `#header .text-white { white-space: normal; color: currentColor; background: transparent; border-color: inherit; }
/* white #fff rgb(0 0 0) */`;
    assert.deepEqual(scanStylesheet(CSS_PATH, clean).findings, []);
  });

  test("dark-variant", () => {
    assert.deepEqual(
      matchesOf(
        scanMarkup("a.html", '<div class="phone:dark:bg-surface dark:md:p-2 dark:border-t">'),
        "dark-variant",
      ),
      ["phone:dark:bg-surface", "dark:md:p-2", "dark:border-t"],
    );
    const css = ".plate-ring { @variant dark { box-shadow: 0 0 0 1px var(--color-plate-edge); } }";
    assert.deepEqual(scanStylesheet(CSS_PATH, css).findings, []);
    const keys = 'const styles = { dark: "https://tiles.openfreemap.org/styles/dark" }; // dark: OS scheme';
    assert.deepEqual(scanMarkup("a.js", keys).findings, []);
  });
});

describe("token regions", () => {
  test("pairs markers with a reason", () => {
    const { errors, regions } = parseTokenRegions(
      "/* theme-lint: tokens-start why */ a /* theme-lint: tokens-end */",
    );
    assert.deepEqual(errors, []);
    assert.equal(regions.length, 1);
  });

  test("rejects unmatched markers, missing reasons, nesting and unknown markers", () => {
    const messages = (text) => parseTokenRegions(text).errors.map(({ message }) => message);
    assert.deepEqual(messages("/* theme-lint: tokens-start why */"), ["unmatched tokens-start marker"]);
    assert.deepEqual(messages("/* theme-lint: tokens-end */"), ["unmatched tokens-end marker"]);
    assert.deepEqual(messages("/* theme-lint: tokens-start */ /* theme-lint: tokens-end */"), [
      "tokens-start marker needs a reason",
    ]);
    assert.deepEqual(
      messages(
        "/* theme-lint: tokens-start a */ /* theme-lint: tokens-start b */ /* theme-lint: tokens-end */",
      ),
      ["token regions do not nest"],
    );
    assert.deepEqual(messages("/* theme-lint: tokens-start a */ /* theme-lint: tokens-end b */"), [
      "tokens-end marker takes no text",
    ]);
    assert.deepEqual(messages("/* theme-lint: ignore */"), ['unknown theme-lint marker "ignore"']);
  });
});

describe("allowlist", () => {
  const entry = {
    count: 2,
    file: "ocg-server/static/js/common/charts/charts.js",
    match: "--color-primary-<N>",
    reason: "ECharts palette reads the numbered ramp",
    rule: "numbered-primary",
  };
  const finding = (line, match = `--color-primary-${line}00`) => ({
    line,
    match,
    message: "m",
    path: entry.file,
    rule: "numbered-primary",
  });

  test("allows up to count matches, with <N> standing for a shade", () => {
    const { entries, errors } = parseAllowlist(JSON.stringify([entry]));
    assert.deepEqual(errors, []);
    const result = applyAllowlist([finding(1), finding(2), finding(3, "bg-primary-500")], entries);
    assert.deepEqual(
      result.unallowed.map(({ match }) => match),
      ["bg-primary-500"],
    );
    assert.deepEqual(result.errors, []);
  });

  test("reports over-count matches as findings", () => {
    const { entries } = parseAllowlist(JSON.stringify([entry]));
    const result = applyAllowlist([finding(1), finding(2), finding(3)], entries);
    assert.equal(result.unallowed.length, 1);
    assert.match(result.unallowed[0].message, /exceeds allowlist count 2/u);
  });

  test("reports under-count entries as stale", () => {
    const { entries } = parseAllowlist(JSON.stringify([entry]));
    const result = applyAllowlist([finding(1)], entries);
    assert.equal(result.errors.length, 1);
    assert.match(result.errors[0].message, /stale allowlist entry .* count 2, found 1/u);
  });

  test("rejects malformed entries", () => {
    const { reason, ...withoutReason } = entry;
    assert.ok(reason);
    const { entries, errors } = parseAllowlist(
      JSON.stringify(
        [withoutReason, { ...entry, reason: " " }, { ...entry, count: 0 }, { ...entry, rule: "nope" }],
        null,
        2,
      ),
    );
    assert.deepEqual(entries, []);
    assert.deepEqual(
      errors.map(({ message }) => message),
      [
        "malformed allowlist: entry 1: missing reason",
        "malformed allowlist: entry 2: missing reason",
        "malformed allowlist: entry 3: count must be a positive integer",
        'malformed allowlist: entry 4: unknown rule "nope"',
      ],
    );
    assert.equal(parseAllowlist("{}").errors.length, 1);
  });
});

describe("run", () => {
  test("a clean tree passes", () => {
    assert.deepEqual(run({ root: writeRepo({}) }), { errors: [], exitCode: 0 });
  });

  test("findings fail with one line each", () => {
    const root = writeRepo({
      "ocg-server/templates/a.html": '<div class="bg-white">\n<a class="text-primary-500">',
    });
    assert.deepEqual(run({ root }), {
      errors: [
        "ocg-server/templates/a.html:1: raw-white-black: bg-white: use a semantic token (surface, raised, plate, on-fill, on-primary) or stone-900 text",
        "ocg-server/templates/a.html:2: numbered-primary: text-primary-500: use a primary role (fill, tint, fg, edge or halo in the @theme static block)",
      ],
      exitCode: 1,
    });
  });

  test("allowlisted findings pass, stale and malformed entries fail", () => {
    const entry = {
      count: 1,
      file: "ocg-server/templates/a.html",
      match: "bg-white",
      reason: "r",
      rule: "raw-white-black",
    };
    const allowed = writeRepo({
      [ALLOWLIST_PATH]: JSON.stringify([entry]),
      "ocg-server/templates/a.html": '<a class="bg-white">',
    });
    assert.deepEqual(run({ root: allowed }), { errors: [], exitCode: 0 });
    const stale = run({ root: writeRepo({ [ALLOWLIST_PATH]: JSON.stringify([entry]) }) });
    assert.equal(stale.exitCode, 1);
    assert.deepEqual(stale.errors, [
      'tests/theme-lint/theme-lint-allowlist.json:1: allowlist: stale allowlist entry for ocg-server/templates/a.html raw-white-black "bg-white": count 1, found 0',
    ]);
    const malformed = run({
      root: writeRepo({ [ALLOWLIST_PATH]: JSON.stringify([{ ...entry, reason: "" }]) }),
    });
    assert.equal(malformed.exitCode, 1);
    assert.deepEqual(malformed.errors, [
      "tests/theme-lint/theme-lint-allowlist.json:1: allowlist: malformed allowlist: entry 1: missing reason",
    ]);
  });

  test("unmapped-shade reads the light constants of styles.src.css and honors the allowlist", () => {
    // A remapped shade without a constant fails
    const template = { "ocg-server/templates/a.html": '<p class="text-green-700">' };
    assert.deepEqual(run({ root: writeRepo(template) }), {
      errors: [
        "ocg-server/templates/a.html:1: unmapped-shade: text-green-700: green-700 has no --ocg-light-green-700 constant, so it stays light in dark",
      ],
      exitCode: 1,
    });
    // A constant declared in styles.src.css clears it
    const constant = `${CLEAN_CSS}:root {
  /* theme-lint: tokens-start light palette constants */
  --ocg-light-green-700: #15803d;
  /* theme-lint: tokens-end */
}
`;
    assert.deepEqual(run({ root: writeRepo({ ...template, [CSS_PATH]: constant }) }), {
      errors: [],
      exitCode: 0,
    });
    // So does an allowlist entry
    const entry = {
      count: 1,
      file: "ocg-server/templates/a.html",
      match: "text-green-<N>",
      reason: "r",
      rule: "unmapped-shade",
    };
    assert.deepEqual(run({ root: writeRepo({ ...template, [ALLOWLIST_PATH]: JSON.stringify([entry]) }) }), {
      errors: [],
      exitCode: 0,
    });
  });

  test("marker errors fail", () => {
    const root = writeRepo({ [CSS_PATH]: `${CLEAN_CSS}/* theme-lint: tokens-start */` });
    assert.deepEqual(run({ root }), {
      errors: [
        "ocg-server/static/css/styles.src.css:7: token-region: tokens-start marker needs a reason",
        "ocg-server/static/css/styles.src.css:7: token-region: unmatched tokens-start marker",
      ],
      exitCode: 1,
    });
  });

  test("templates skip emails and static JS is read", () => {
    const root = writeRepo({
      "ocg-server/static/js/a.js": 'el.className = "text-black";',
      "ocg-server/templates/macros/email.html": '<p style="color: #000">',
      "ocg-server/templates/notifications/base.html": '<p class="bg-white">',
    });
    const { errors } = run({ root });
    assert.deepEqual(
      errors.map((line) => line.split(":")[0]),
      ["ocg-server/static/js/a.js"],
    );
  });

  test("the command line rejects arguments", () => {
    const { status, stderr } = spawnSync(process.execPath, [SCRIPT_PATH, "--summary"], { encoding: "utf8" });
    assert.equal(status, 1);
    assert.equal(stderr, "error: unknown argument --summary; usage: theme-lint.mjs\n");
  });

  test("the repository passes", () => {
    assert.deepEqual(run(), { errors: [], exitCode: 0 });
  });
});
