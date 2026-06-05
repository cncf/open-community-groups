/**
 * Returns true when character at index is escaped by odd trailing backslashes.
 * @param {string} text Source text.
 * @param {number} index Character index.
 * @returns {boolean} True when character is escaped.
 */
const isEscapedByOddBackslashes = (text, index) => {
  let backslashCount = 0;
  for (let cursor = index - 1; cursor >= 0 && text[cursor] === "\\"; cursor -= 1) {
    backslashCount += 1;
  }
  return backslashCount % 2 === 1;
};

/**
 * Splits selectors by comma while keeping function contents intact.
 * @param {string} selectorText Raw selector list.
 * @returns {string[]} Selector list.
 */
const splitSelectors = (selectorText) => {
  const selectors = [];
  let current = "";
  let bracketDepth = 0;
  let parenDepth = 0;
  let quoteChar = "";

  for (let index = 0; index < selectorText.length; index += 1) {
    const char = selectorText[index];

    if (quoteChar) {
      current += char;
      if (char === quoteChar && !isEscapedByOddBackslashes(selectorText, index)) {
        quoteChar = "";
      }
      continue;
    }

    if (char === "'" || char === '"') {
      quoteChar = char;
      current += char;
      continue;
    }

    if (char === "(") {
      parenDepth += 1;
      current += char;
      continue;
    }

    if (char === ")") {
      parenDepth = Math.max(0, parenDepth - 1);
      current += char;
      continue;
    }

    if (char === "[") {
      bracketDepth += 1;
      current += char;
      continue;
    }

    if (char === "]") {
      bracketDepth = Math.max(0, bracketDepth - 1);
      current += char;
      continue;
    }

    if (char === "," && parenDepth === 0 && bracketDepth === 0) {
      selectors.push(current.trim());
      current = "";
      continue;
    }

    current += char;
  }

  if (current.trim()) {
    selectors.push(current.trim());
  }

  return selectors;
};

/**
 * Adds scope selector to a single CSS selector.
 * @param {string} selector CSS selector.
 * @param {string} scope Scope selector.
 * @returns {string} Scoped selector.
 */
const scopeSelector = (selector, scope) => {
  if (!selector) {
    return selector;
  }

  if (selector.includes(scope)) {
    return selector;
  }

  const withRootReplaced = selector.replace(
    /(^|[\s>+~])(:root|html|body)(?=($|[\s>+~.#[:]))/g,
    (match, prefix) => `${prefix}${scope}`,
  );

  if (withRootReplaced.includes(scope)) {
    return withRootReplaced;
  }

  return `${scope} ${withRootReplaced}`;
};

/**
 * Returns the matching closing brace index.
 * @param {string} cssText CSS text.
 * @param {number} openBraceIndex Opening brace index.
 * @returns {number} Closing brace index.
 */
const findMatchingBrace = (cssText, openBraceIndex) => {
  let depth = 0;
  let quoteChar = "";

  for (let index = openBraceIndex; index < cssText.length; index += 1) {
    const char = cssText[index];
    const nextChar = cssText[index + 1];

    if (quoteChar) {
      if (char === quoteChar && !isEscapedByOddBackslashes(cssText, index)) {
        quoteChar = "";
      }
      continue;
    }

    if (char === "'" || char === '"') {
      quoteChar = char;
      continue;
    }

    if (char === "/" && nextChar === "*") {
      const commentEnd = cssText.indexOf("*/", index + 2);
      if (commentEnd === -1) {
        return cssText.length - 1;
      }
      index = commentEnd + 1;
      continue;
    }

    if (char === "{") {
      depth += 1;
      continue;
    }

    if (char === "}") {
      depth -= 1;
      if (depth === 0) {
        return index;
      }
    }
  }

  return cssText.length - 1;
};

/**
 * Finds next top-level rule delimiter.
 * @param {string} cssText CSS text.
 * @param {number} startIndex Search start.
 * @returns {{char: string, index: number}|null} Next delimiter.
 */
const findTopLevelDelimiter = (cssText, startIndex) => {
  let bracketDepth = 0;
  let parenDepth = 0;
  let quoteChar = "";

  for (let index = startIndex; index < cssText.length; index += 1) {
    const char = cssText[index];
    const nextChar = cssText[index + 1];

    if (quoteChar) {
      if (char === quoteChar && !isEscapedByOddBackslashes(cssText, index)) {
        quoteChar = "";
      }
      continue;
    }

    if (char === "'" || char === '"') {
      quoteChar = char;
      continue;
    }

    if (char === "/" && nextChar === "*") {
      const commentEnd = cssText.indexOf("*/", index + 2);
      if (commentEnd === -1) {
        return null;
      }
      index = commentEnd + 1;
      continue;
    }

    if (char === "(") {
      parenDepth += 1;
      continue;
    }

    if (char === ")") {
      parenDepth = Math.max(0, parenDepth - 1);
      continue;
    }

    if (char === "[") {
      bracketDepth += 1;
      continue;
    }

    if (char === "]") {
      bracketDepth = Math.max(0, bracketDepth - 1);
      continue;
    }

    if (parenDepth === 0 && bracketDepth === 0 && (char === "{" || char === ";")) {
      return { char, index };
    }
  }

  return null;
};

/**
 * Scopes a CSS rule list to a selector.
 * @param {string} cssText CSS text.
 * @param {string} scope Scope selector.
 * @returns {string} Scoped CSS text.
 */
export const scopeCssRules = (cssText, scope) => {
  const noScopeAtRules = [
    "@font-face",
    "@keyframes",
    "@-webkit-keyframes",
    "@property",
    "@counter-style",
    "@page",
  ];
  const recursiveAtRules = ["@media", "@supports", "@document", "@container", "@layer"];

  let scopedCss = "";
  let cursor = 0;

  while (cursor < cssText.length) {
    const delimiter = findTopLevelDelimiter(cssText, cursor);
    if (!delimiter) {
      scopedCss += cssText.slice(cursor);
      break;
    }

    if (delimiter.char === ";") {
      scopedCss += cssText.slice(cursor, delimiter.index + 1);
      cursor = delimiter.index + 1;
      continue;
    }

    const prelude = cssText.slice(cursor, delimiter.index).trim();
    const blockEnd = findMatchingBrace(cssText, delimiter.index);
    const blockBody = cssText.slice(delimiter.index + 1, blockEnd);

    if (!prelude.startsWith("@")) {
      const scopedPrelude = splitSelectors(prelude)
        .map((selector) => scopeSelector(selector, scope))
        .join(", ");
      scopedCss += `${scopedPrelude}{${blockBody}}`;
      cursor = blockEnd + 1;
      continue;
    }

    const lowerPrelude = prelude.toLowerCase();
    if (noScopeAtRules.some((rule) => lowerPrelude.startsWith(rule))) {
      scopedCss += `${prelude}{${blockBody}}`;
      cursor = blockEnd + 1;
      continue;
    }

    if (recursiveAtRules.some((rule) => lowerPrelude.startsWith(rule))) {
      scopedCss += `${prelude}{${scopeCssRules(blockBody, scope)}}`;
      cursor = blockEnd + 1;
      continue;
    }

    scopedCss += `${prelude}{${blockBody}}`;
    cursor = blockEnd + 1;
  }

  return scopedCss;
};
