import { expect } from "@open-wc/testing";

/** Loads the inbox conversation template source and collapses its whitespace. */
const loadTemplate = async () => {
  const response = await fetch("/ocg-server/templates/dashboard/inbox_conversation.html");

  expect(response.ok).to.equal(true);

  return (await response.text()).replace(/\s+/g, " ").trim();
};

describe("dashboard inbox conversation template", () => {
  it("renders the message count per scope", async () => {
    // Load the conversation template.
    const template = await loadTemplate();

    // Verify the message count element branches on the dashboard scope.
    const countIndex = template.indexOf("{{ conversation.messages.len() }} message");
    const iconStart = template.lastIndexOf("<span ", template.lastIndexOf("icon-email", countIndex));
    const countStart = template.lastIndexOf("<span ", iconStart - 1);

    expect(countIndex).to.be.greaterThan(-1);
    expect(template.slice(countStart, iconStart)).to.match(
      /^<span class="\{% if scope\.is_group\(\) %\}[^"]*\{% else %\}[^"]*\{% endif %\}[^"]*">/,
    );
  });
});
