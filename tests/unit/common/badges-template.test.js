import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch("/ocg-server/templates/macros/badges.html");

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("badge macros template", () => {
  it("uses the compact uppercase badge foundation for dashboard badge variants", async () => {
    // Load the badge macros template and isolate the invitation badge variants.
    const template = normalizeWhitespace(await loadTemplate());
    const invitationBadge = template.slice(
      template.indexOf("{% macro invitation_badge"),
      template.indexOf("{% endmacro invitation_badge"),
    );

    // Verify shared badge styles and invitation state borders stay consistent.
    expect(template).to.include(
      'class="custom-badge inline-block max-w-full truncate px-2.5 py-0.5 text-stone-900',
    );
    expect(invitationBadge.match(/<span class="custom-badge bg-/g)).to.have.lengthOf(3);
    expect(invitationBadge).to.include(
      "{% if with_border %}border-green-800{% else %}border-transparent{% endif %}",
    );
    expect(invitationBadge).to.include(
      "{% if with_border %}border-red-800{% else %}border-transparent{% endif %}",
    );
    expect(invitationBadge).to.include(
      "{% if with_border %}border-yellow-800{% else %}border-transparent{% endif %}",
    );
  });

  it("uses semantic payment colors without blue states", async () => {
    // Load and isolate the shared payment badge before checking its palette.
    const template = normalizeWhitespace(await loadTemplate());
    const paymentStatusBadge = template.slice(
      template.indexOf("{% macro payment_status_badge"),
      template.indexOf("{% endmacro payment_status_badge"),
    );

    // Verify terminal, active, and neutral payment states use semantic colors.
    expect(paymentStatusBadge).to.include('label.as_bytes() == "Paid".as_bytes()');
    expect(paymentStatusBadge).to.include("border-green-800 bg-green-100");
    expect(paymentStatusBadge).to.include('label.as_bytes() == "Refund requested".as_bytes()');
    expect(paymentStatusBadge).to.include("border-amber-800 bg-amber-100");
    expect(paymentStatusBadge).to.include('label.as_bytes() == "Refund rejected".as_bytes()');
    expect(paymentStatusBadge).to.include("border-red-800 bg-red-100");
    expect(paymentStatusBadge).to.include('tone.as_bytes() == "danger".as_bytes()');
    expect(paymentStatusBadge).to.include("border-stone-500 bg-stone-100");
    expect(paymentStatusBadge).not.to.include("blue");
  });
});
