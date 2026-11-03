import { expect } from "../../fixtures.js";

import { queryE2eDatabase } from "../../database.js";
import { navigateToPath } from "../../utils.js";

/** Deletes a browser-created auth user by exact username. */
export const deleteUserByUsername = (username) => {
  const escapedUsername = username.replace(/'/g, "''");

  queryE2eDatabase(`delete from "user" where username = '${escapedUsername}'`);
};

/** Fills the email sign-up form using the provided account details. */
export const fillSignUpForm = async (page, user) => {
  await page.getByLabel("Full Name").fill(user.name);
  await page.getByLabel("Email Address").fill(user.email);
  await page.getByLabel("Username").fill(user.username);
  await page.getByRole("textbox", { name: "Password required", exact: true }).fill(user.password);
  await page.getByRole("textbox", { name: "Confirm Password required" }).fill(user.password);
};

/** Logs in using email username and password credentials. */
export const logInWithEmail = async (page, user) => {
  await expect(page.getByRole("heading", { name: "Log In" })).toBeVisible();
  await page.getByLabel("Username").fill(user.username);
  await page.getByRole("textbox", { name: "Password required" }).fill(user.password);
  await page.getByRole("button", { name: "Sign In" }).click();
};

/** Reads the created user id for notification assertions. */
export const readUserIdByUsername = (username) => {
  const escapedUsername = username.replace(/'/g, "''");

  return queryE2eDatabase(`select user_id from "user" where username = '${escapedUsername}'`) || null;
};

/** Completes the sign-up form using email and password credentials. */
export const signUpWithEmail = async (page, user) => {
  await navigateToPath(page, "/sign-up");

  await expect(page.getByRole("heading", { name: "Sign Up" })).toBeVisible();
  await fillSignUpForm(page, user);

  await page.getByRole("button", { name: "Create Account" }).click();
  await expect(page.getByRole("heading", { name: "Log In" })).toBeVisible();
};

/** Waits until sign-up persistence creates an email verification code. */
export const waitForEmailVerificationCode = async (email) => {
  let verificationCode = null;

  await expect
    .poll(
      () => {
        verificationCode = readEmailVerificationCode(email);
        return verificationCode;
      },
      {
        intervals: [250],
        message: `Timed out waiting for verification code for ${email}`,
        timeout: 10_000,
      },
    )
    .not.toBeNull();

  return verificationCode;
};

/** Reads the email verification code for a newly created user from the E2E DB. */
const readEmailVerificationCode = (email) => {
  const escapedEmail = email.replace(/'/g, "''");
  const sql = `
    select evc.email_verification_code_id
    from email_verification_code evc
    join "user" u on u.user_id = evc.user_id
    where u.email = '${escapedEmail}'
  `;

  const output = queryE2eDatabase(sql);

  return output || null;
};
