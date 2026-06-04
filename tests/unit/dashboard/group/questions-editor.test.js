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
    // Mount an editor with a selectable registration question.
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

    // Verify renders serde_qs hidden inputs for registration questions.
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
    // Mount an editor with a free-text question that has stale options.
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

    // Assert the expected markup is rendered.
    expect(element.querySelector('input[name="registration_questions[0][options][0][id]"]')).to.equal(null);
  });

  it("marks question prompts and selectable options as required", async () => {
    // Mount an editor with an incomplete selectable question.
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

    // Click Edit question.
    await clickButtonByLabel(element, "Edit question");

    // Verify marks question prompts and selectable options as required.
    expect(element.querySelector("#question-prompt-draft")?.required).to.equal(true);
    expect(element.querySelector('input[aria-label="Option 1"]')?.required).to.equal(true);
  });

  it("keeps one option available for selectable questions", async () => {
    // Mount an editor with one selectable option.
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

    // Click Edit question.
    await clickButtonByLabel(element, "Edit question");

    // Set up remove button.
    const removeButton = element.querySelector('button[aria-label="Remove option"]');

    // Verify keeps one option available for selectable questions.
    expect(removeButton.disabled).to.equal(true);

    // Click the remove button.
    removeButton.click();
    await element.updateComplete;

    // Assert the expected number of elements is rendered.
    expect(element.querySelectorAll('input[aria-label^="Option"]').length).to.equal(1);
    expect(
      element.querySelector('input[name="registration_questions[0][options][0][label]"]')?.value,
    ).to.equal("Vegetarian");
  });

  it("adds questions through the modal editor", async () => {
    // Mount an empty editor before opening the add-question modal.
    const element = await mountLitComponent("questions-editor", {
      name: "registration_questions",
    });

    // Run click button.
    await clickButton(element, "Add question");

    // Answer the required form question.
    element.querySelector("#question-prompt-draft").value = "Company name";
    element.querySelector("#question-prompt-draft").dispatchEvent(new Event("input"));

    // Call click button.
    await clickButton(element, "Add question");

    // Verify adds questions through the modal editor.
    expect(element.textContent).to.include("Company name");
    expect(element.textContent).to.include("1 question");
    expect(element.querySelector('input[name="registration_questions[0][prompt]"]')?.value).to.equal(
      "Company name",
    );
  });

  it("edits selectable questions through the modal editor", async () => {
    // Mount an editor with a selectable question to edit.
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

    // Click Edit question.
    await clickButtonByLabel(element, "Edit question");

    // Answer the required form question.
    element.querySelector("#question-prompt-draft").value = "Dietary restrictions";
    element.querySelector("#question-prompt-draft").dispatchEvent(new Event("input"));
    element.querySelector('input[aria-label="Option 1"]').value = "Vegan";
    element.querySelector('input[aria-label="Option 1"]').dispatchEvent(new Event("input"));

    // Click Save question.
    await clickButton(element, "Save question");

    // Verify edits selectable questions through the modal editor.
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
    // Mount an editor with two selectable options.
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

    // Click Edit question.
    await clickButtonByLabel(element, "Edit question");
    element
      .querySelector('button[aria-label="Reorder option"]')
      .dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown" }));
    await element.updateComplete;
    await clickButton(element, "Save question");

    // Verify reorders selectable question options through the modal editor.
    expect(
      element.querySelector('input[name="registration_questions[0][options][0][label]"]')?.value,
    ).to.equal("Vegan");
    expect(
      element.querySelector('input[name="registration_questions[0][options][1][label]"]')?.value,
    ).to.equal("Vegetarian");
  });

  it("reorders questions from the question card handle", async () => {
    // Mount an editor with two reorderable questions.
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

    // Verify reorders questions from the question card handle.
    expect(element.querySelector('input[name="registration_questions[0][prompt]"]')?.value).to.equal(
      "Second question",
    );
    expect(element.querySelector('input[name="registration_questions[1][prompt]"]')?.value).to.equal(
      "First question",
    );
  });

  it("does not reorder questions when the editor is disabled", async () => {
    // Mount a disabled editor with two questions.
    const element = await mountLitComponent("questions-editor", {
      disabled: true,
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

    // Set up reorder button.
    const reorderButton = element.querySelector('button[aria-label="Reorder question"]');

    // Verify does not reorder questions when the editor is disabled.
    expect(reorderButton.disabled).to.equal(true);
    expect(reorderButton.getAttribute("draggable")).to.equal("false");

    // Dispatch the form event.
    reorderButton.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown" }));
    await element.updateComplete;

    // Assert the saved field value.
    expect(element.querySelector('input[name="registration_questions[0][prompt]"]')?.value).to.equal(
      "First question",
    );
    expect(element.querySelector('input[name="registration_questions[1][prompt]"]')?.value).to.equal(
      "Second question",
    );
  });

  it("shows an editable warning when questions have been added", async () => {
    // Mount an editable editor that already has questions.
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

    // Assert the expected copy is rendered.
    expect(element.textContent).to.include(
      "Questionnaire questions cannot be edited after an attendee has submitted answers.",
    );
    expect(element.querySelector("[data-question-editing-warning]")?.classList.contains("w-full")).to.equal(
      true,
    );
  });

  it("does not show the editable warning when questions are locked", async () => {
    // Mount a disabled editor that already has questions.
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

    // Assert the expected copy is rendered.
    expect(element.textContent).not.to.include(
      "Questionnaire questions cannot be edited after an attendee has submitted answers.",
    );
  });

  it("renders selected question types from the questions attribute", async () => {
    // Mount an editor from serialized question attributes.
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

    // Assert the expected copy is rendered.
    expect(element.textContent).to.include("Single select");
    expect(element.textContent).to.include("Multi select");
  });

  it("normalizes questions assigned after render", async () => {
    // Mount an empty editor before assigning questions programmatically.
    const element = await mountLitComponent("questions-editor", {
      name: "registration_questions",
    });

    // Load questions into the editor.
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

    // Verify normalizes questions assigned after render.
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
    // Mount a disabled editor with a selectable question.
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

    // Set up controls.
    const controls = [...element.querySelectorAll('button, input:not([type="hidden"]), select')];

    // Assert that editor controls are rendered.
    expect(controls.length).to.be.greaterThan(0);
    expect(controls.every((control) => control.disabled)).to.equal(true);
  });
});
