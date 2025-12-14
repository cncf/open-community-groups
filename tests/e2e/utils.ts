import { Page, Locator } from "@playwright/test";

// Path constants
export const HOME_PATH = "/";
export const LOGIN_PATH = "/log-in";
export const SIGNUP_PATH = "/sign-up";

// Selector constants
export const LOADING_BUTTON_SELECTOR = "#loading-btn";
export const SWEET_ALERT_SELECTOR = ".swal2-popup";
export const SWEET_ALERT_CONFIRM_SELECTOR = ".swal2-confirm";
export const SWEET_ALERT_CANCEL_SELECTOR = ".swal2-cancel";

// Locator helpers
export const loadingButton = (page: Page): Locator =>
  page.locator(LOADING_BUTTON_SELECTOR);

export const sweetAlert = (page: Page): Locator =>
  page.locator(SWEET_ALERT_SELECTOR);

export const sweetAlertConfirm = (page: Page): Locator =>
  page.locator(SWEET_ALERT_CONFIRM_SELECTOR);

export const sweetAlertCancel = (page: Page): Locator =>
  page.locator(SWEET_ALERT_CANCEL_SELECTOR);

// Navigation helpers with retry logic
export const navigateWithRetry = async (
  page: Page,
  url: string,
  options?: { timeout?: number; retries?: number },
): Promise<void> => {
  const timeout = options?.timeout || 60000;
  const retries = options?.retries || 3;

  for (let i = 0; i < retries; i++) {
    try {
      await page.goto(url, { timeout });
      break;
    } catch (error) {
      console.log(
        `Failed to navigate to ${url}, retrying... (${i + 1}/${retries})`,
      );
      if (i === retries - 1) {
        throw error;
      }
    }
  }
};

export const openLoginPage = async (page: Page): Promise<void> => {
  await navigateWithRetry(page, LOGIN_PATH);
};

export const openSignUpPage = async (page: Page): Promise<void> => {
  await navigateWithRetry(page, SIGNUP_PATH);
};

// Wait helpers
export const waitForLoadingComplete = async (
  page: Page,
  selector?: string,
): Promise<void> => {
  const targetSelector = selector || LOADING_BUTTON_SELECTOR;
  await page
    .locator(targetSelector)
    .waitFor({ state: "hidden", timeout: 10000 });
};

export const waitForAlert = async (page: Page): Promise<Locator> => {
  const alert = sweetAlert(page);
  await alert.waitFor({ state: "visible" });
  return alert;
};

export const confirmAlert = async (page: Page): Promise<void> => {
  await sweetAlertConfirm(page).click();
};

export const cancelAlert = async (page: Page): Promise<void> => {
  await sweetAlertCancel(page).click();
};

// Authentication helpers
export const loginWithCredentials = async (
  page: Page,
  username: string,
  password: string,
): Promise<void> => {
  await openLoginPage(page);
  await page.locator("#username").fill(username);
  await page.locator("#password").fill(password);
  await page.locator('button[type="submit"]').click();

  // Wait for login to complete (redirected away from login page)
  await page.waitForURL((url) => !url.pathname.includes("/log-in"), {
    timeout: 10000,
  });
};
