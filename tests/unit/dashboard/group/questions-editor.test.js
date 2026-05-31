import { expect } from "@open-wc/testing";

import "/static/js/dashboard/group/questions-editor.js";
import {
  mountLitComponent,
  mountLitComponentWithAttributes,
  useMountedElementsCleanup,
} from "/tests/unit/test-utils/lit.js";

describe("questions-editor", () => {
  useMountedElementsCleanup("questions-editor");

  const clickButton = async (element, label) => {
    const button = [...element.querySelectorAll("button")]
      .reverse()
      .find((candidate) => candidate.textContent.trim() === label && !candidate.disabled);

    button.click();
    await element.updateComplete;
    return button;
  };

  const clickButtonByLabel = async (element, label) => {
    const button = element.querySelector(`button[aria-label="${label}"]:not(:disabled)`);

    button.click();
    await element.updateComplete;
    return button;
  };

  it("renders serde_qs hidden inputs for registration questions", async () => {
    const element = await mountLitComponent("questions-editor", {
      name: "registration_questions",
      questions: [
        {
          id: "00000000-0000-0000-0000-000000000101",
          kind: "single-select",
          options: [
            {
              id: "00000000-0000-0000-0000-000000000201",
              label: "Vegetarian",
            },
          ],
          prompt: "Meal preference",
          required: true,
        },
      ],
    });

    expect(element.querySelector('input[name="registration_questions_present"]')?.value).to.equal("true");
    expect(element.querySelector('input[name="registration_questions[0][id]"]')?.value).to.equal(
      "00000000-0000-0000-0000-000000000101",
    );
    expect(element.querySelector('input[name="registration_questions[0][kind]"]')?.value).to.equal(
      "single-select",
    );
    expect(element.querySelector('input[name="registration_questions[0][prompt]"]')?.value).to.equal(
      "Meal preference",
    );
    expect(element.querySelector('input[name="registration_questions[0][required]"]')?.value).to.equal(
      "true",
    );
    expect(element.querySelector('input[name="registration_questions[0][options][0][id]"]')?.value).to.equal(
      "00000000-0000-0000-0000-000000000201",
    );
    expect(
      element.querySelector('input[name="registration_questions[0][options][0][label]"]')?.value,
    ).to.equal("Vegetarian");
  });

  it("does not submit options for free-text questions", async () => {
    const element = await mountLitComponent("questions-editor", {
      name: "registration_questions",
      questions: [
        {
          id: "00000000-0000-0000-0000-000000000101",
          kind: "free-text",
          options: [
            {
              id: "00000000-0000-0000-0000-000000000201",
              label: "Stale option",
            },
          ],
          prompt: "Accessibility needs",
          required: false,
        },
      ],
    });

    expect(element.querySelector('input[name="registration_questions[0][options][0][id]"]')).to.equal(null);
  });

  it("marks question prompts and selectable options as required", async () => {
    const element = await mountLitComponent("questions-editor", {
      name: "registration_questions",
      questions: [
        {
          id: "00000000-0000-0000-0000-000000000101",
          kind: "single-select",
          options: [
            {
              id: "00000000-0000-0000-0000-000000000201",
              label: "",
            },
          ],
          prompt: "",
          required: false,
        },
      ],
    });

    await clickButtonByLabel(element, "Edit question");

    expect(element.querySelector("#question-prompt-draft")?.required).to.equal(true);
    expect(element.querySelector('input[aria-label="Option 1"]')?.required).to.equal(true);
  });

  it("keeps one option available for selectable questions", async () => {
    const element = await mountLitComponent("questions-editor", {
      name: "registration_questions",
      questions: [
        {
          id: "00000000-0000-0000-0000-000000000101",
          kind: "single-select",
          options: [
            {
              id: "00000000-0000-0000-0000-000000000201",
              label: "Vegetarian",
            },
          ],
          prompt: "Meal preference",
          required: false,
        },
      ],
    });

    await clickButtonByLabel(element, "Edit question");

    const removeButton = element.querySelector('button[aria-label="Remove option"]');

    expect(removeButton.disabled).to.equal(true);

    removeButton.click();
    await element.updateComplete;

    expect(element.querySelectorAll('input[aria-label^="Option"]').length).to.equal(1);
    expect(
      element.querySelector('input[name="registration_questions[0][options][0][label]"]')?.value,
    ).to.equal("Vegetarian");
  });

  it("adds questions through the modal editor", async () => {
    const element = await mountLitComponent("questions-editor", {
      name: "registration_questions",
    });

    await clickButton(element, "Add question");

    element.querySelector("#question-prompt-draft").value = "Company name";
    element.querySelector("#question-prompt-draft").dispatchEvent(new Event("input"));

    await clickButton(element, "Add question");

    expect(element.textContent).to.include("Company name");
    expect(element.textContent).to.include("1 question");
    expect(element.querySelector('input[name="registration_questions[0][prompt]"]')?.value).to.equal(
      "Company name",
    );
  });

  it("edits selectable questions through the modal editor", async () => {
    const element = await mountLitComponent("questions-editor", {
      name: "registration_questions",
      questions: [
        {
          id: "00000000-0000-0000-0000-000000000101",
          kind: "single-select",
          options: [
            {
              id: "00000000-0000-0000-0000-000000000201",
              label: "Vegetarian",
            },
          ],
          prompt: "Meal preference",
          required: false,
        },
      ],
    });

    await clickButtonByLabel(element, "Edit question");

    element.querySelector("#question-prompt-draft").value = "Dietary restrictions";
    element.querySelector("#question-prompt-draft").dispatchEvent(new Event("input"));
    element.querySelector('input[aria-label="Option 1"]').value = "Vegan";
    element.querySelector('input[aria-label="Option 1"]').dispatchEvent(new Event("input"));

    await clickButton(element, "Save question");

    expect(element.textContent).to.include("Dietary restrictions");
    expect(element.textContent).to.include("Vegan");
    expect(element.querySelector('input[name="registration_questions[0][prompt]"]')?.value).to.equal(
      "Dietary restrictions",
    );
    expect(
      element.querySelector('input[name="registration_questions[0][options][0][label]"]')?.value,
    ).to.equal("Vegan");
  });

  it("reorders selectable question options through the modal editor", async () => {
    const element = await mountLitComponent("questions-editor", {
      name: "registration_questions",
      questions: [
        {
          id: "00000000-0000-0000-0000-000000000101",
          kind: "single-select",
          options: [
            {
              id: "00000000-0000-0000-0000-000000000201",
              label: "Vegetarian",
            },
            {
              id: "00000000-0000-0000-0000-000000000202",
              label: "Vegan",
            },
          ],
          prompt: "Meal preference",
          required: false,
        },
      ],
    });

    await clickButtonByLabel(element, "Edit question");
    element
      .querySelector('button[aria-label="Reorder option"]')
      .dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown" }));
    await element.updateComplete;
    await clickButton(element, "Save question");

    expect(
      element.querySelector('input[name="registration_questions[0][options][0][label]"]')?.value,
    ).to.equal("Vegan");
    expect(
      element.querySelector('input[name="registration_questions[0][options][1][label]"]')?.value,
    ).to.equal("Vegetarian");
  });

  it("reorders questions from the question card handle", async () => {
    const element = await mountLitComponent("questions-editor", {
      name: "registration_questions",
      questions: [
        {
          id: "00000000-0000-0000-0000-000000000101",
          kind: "free-text",
          options: [],
          prompt: "First question",
          required: false,
        },
        {
          id: "00000000-0000-0000-0000-000000000102",
          kind: "free-text",
          options: [],
          prompt: "Second question",
          required: true,
        },
      ],
    });

    element
      .querySelector('button[aria-label="Reorder question"]')
      .dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown" }));
    await element.updateComplete;

    expect(element.querySelector('input[name="registration_questions[0][prompt]"]')?.value).to.equal(
      "Second question",
    );
    expect(element.querySelector('input[name="registration_questions[1][prompt]"]')?.value).to.equal(
      "First question",
    );
  });

  it("shows an editable warning when questions have been added", async () => {
    const element = await mountLitComponent("questions-editor", {
      name: "registration_questions",
      questions: [
        {
          id: "00000000-0000-0000-0000-000000000101",
          kind: "free-text",
          options: [],
          prompt: "Accessibility needs",
          required: false,
        },
      ],
    });

    expect(element.textContent).to.include(
      "Questionnaire questions cannot be edited after an attendee has submitted answers.",
    );
    expect(element.querySelector("[data-question-editing-warning]")?.classList.contains("w-full")).to.equal(
      true,
    );
  });

  it("does not show the editable warning when questions are locked", async () => {
    const element = await mountLitComponent("questions-editor", {
      disabled: true,
      questions: [
        {
          id: "00000000-0000-0000-0000-000000000101",
          kind: "free-text",
          options: [],
          prompt: "Accessibility needs",
          required: false,
        },
      ],
    });

    expect(element.textContent).not.to.include(
      "Questionnaire questions cannot be edited after an attendee has submitted answers.",
    );
  });

  it("renders selected question types from the questions attribute", async () => {
    const element = await mountLitComponentWithAttributes("questions-editor", {
      attributes: {
        questions: JSON.stringify([
          {
            id: "00000000-0000-0000-0000-000000000101",
            kind: "single-select",
            options: [
              {
                id: "00000000-0000-0000-0000-000000000201",
                label: "Vegetarian",
              },
            ],
            prompt: "Meal preference",
            required: true,
          },
          {
            id: "00000000-0000-0000-0000-000000000102",
            kind: "multi-select",
            options: [
              {
                id: "00000000-0000-0000-0000-000000000202",
                label: "Rust",
              },
            ],
            prompt: "Topics",
            required: false,
          },
        ]),
      },
    });

    expect(element.textContent).to.include("Single select");
    expect(element.textContent).to.include("Multi select");
  });

  it("normalizes questions assigned after render", async () => {
    const element = await mountLitComponent("questions-editor", {
      name: "registration_questions",
    });

    element.questions = [
      {
        kind: "free-text",
        options: [
          {
            id: "00000000-0000-0000-0000-000000000201",
            label: "Stale option",
          },
        ],
        prompt: "Accessibility needs",
      },
    ];
    await element.updateComplete;

    expect(element.querySelector('input[name="registration_questions[0][id]"]')?.value).to.not.equal("");
    expect(element.querySelector('input[name="registration_questions[0][kind]"]')?.value).to.equal(
      "free-text",
    );
    expect(element.querySelector('input[name="registration_questions[0][required]"]')?.value).to.equal(
      "false",
    );
    expect(element.querySelector('input[name="registration_questions[0][options][0][id]"]')).to.equal(null);
  });

  it("disables visible controls when disabled", async () => {
    const element = await mountLitComponent("questions-editor", {
      disabled: true,
      questions: [
        {
          id: "00000000-0000-0000-0000-000000000101",
          kind: "single-select",
          options: [
            {
              id: "00000000-0000-0000-0000-000000000201",
              label: "Vegetarian",
            },
          ],
          prompt: "Meal preference",
          required: true,
        },
      ],
    });

    const controls = [...element.querySelectorAll('button, input:not([type="hidden"]), select')];

    expect(controls.length).to.be.greaterThan(0);
    expect(controls.every((control) => control.disabled)).to.equal(true);
  });
});
