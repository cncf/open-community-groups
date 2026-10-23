// Isolated server and database stacks prepared by `just e2e-tests-parallel`, one per worker.
// The recipe lists them in `OCG_E2E_STACKS`; single-stack runs leave it unset.

/**
 * Reads the stacks listed in `OCG_E2E_STACKS`.
 * @returns {{baseUrl: string, dbName: string}[]} Stacks, or an empty list for a single-stack run.
 */
export const getE2eStacks = () => {
  const value = process.env.OCG_E2E_STACKS;

  if (!value) {
    return [];
  }

  const message = "OCG_E2E_STACKS must be a JSON array of { baseUrl, dbName } objects";
  let stacks;

  try {
    stacks = JSON.parse(value);
  } catch (error) {
    throw new Error(message, { cause: error });
  }

  if (!Array.isArray(stacks) || stacks.some((stack) => !stack?.baseUrl || !stack?.dbName)) {
    throw new Error(message);
  }

  return stacks;
};

/**
 * Points the current worker process at the stack matching its parallel index.
 *
 * Playwright runs at most one worker per parallel index at a time and sets `TEST_PARALLEL_INDEX`
 * before the worker loads the config, so rewriting the E2E contract here reaches the config's
 * `baseURL` and every helper that reads the contract on import. The runner process has no
 * parallel index and keeps the contract unchanged.
 * @param {{baseUrl: string, dbName: string}[]} stacks - Stacks from `getE2eStacks`.
 */
export const bindWorkerToStack = (stacks) => {
  const parallelIndex = process.env.TEST_PARALLEL_INDEX;

  if (stacks.length === 0 || parallelIndex === undefined) {
    return;
  }

  const stack = stacks[Number(parallelIndex)];

  if (!stack) {
    throw new Error(`E2E worker ${parallelIndex} has no stack; run at most ${stacks.length} workers`);
  }

  process.env.OCG_E2E_BASE_URL = stack.baseUrl;
  process.env.OCG_E2E_DB_NAME = stack.dbName;
};
