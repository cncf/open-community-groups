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

  const getLabeledControl = (element, labelText) => {
    const label = [...element.querySelectorAll("label[for]")].find(
      (candidate) => candidate.textContent.trim() === labelText,
    );

    return label ? document.getElementById(label.htmlFor) : null;
  };

  const getAddQuestionButton = (element) =>
    [...element.querySelectorAll("button")].find(
      (button) => button.textContent.trim() === "Add question" && !button.closest("[data-question-modal]"),
    );

  const getQuestionModal = (element) => element.querySelector('[role="dialog"]');

  const waitForFocus = async (element) => {
    await element.updateComplete;
    await Promise.resolve();
  };

  const buildFreeTextQuestion = (id, prompt) => ({
    id,
    kind: "free-text",
    options: [],
    prompt,
    required: false,
  });

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
    expect(
      [...element.querySelectorAll(".custom-badge")].some(
        (badge) => badge.textContent.trim() === "Vegetarian",
      ),
    ).to.equal(true);
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
    expect(getLabeledControl(element, "Question")?.required).to.equal(true);
    expect(element.querySelector('input[aria-label="Option 1"]')?.required).to.equal(true);
    expect(element.querySelector(".form-legend")?.textContent).to.include(
      "Required questions must be answered. Optional questions can be skipped.",
    );
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
    getLabeledControl(element, "Question").value = "Company name";
    getLabeledControl(element, "Question").dispatchEvent(new Event("input"));

    // Call click button.
    await clickButton(element, "Add question");

    // Verify adds questions through the modal editor.
    expect(element.textContent).to.include("Company name");
    expect(element.textContent).to.include("1 question");
    expect(element.querySelector('input[name="registration_questions[0][prompt]"]')?.value).to.equal(
      "Company name",
    );
  });

  it("uses a full-size secondary action with a visible icon for adding questions", async () => {
    // Mount an empty editor and locate the add-question action.
    const element = await mountLitComponent("questions-editor", {
      name: "registration_questions",
    });
    const addQuestionButton = [...element.querySelectorAll("button")].find(
      (button) => button.textContent.trim() === "Add question",
    );
    const addQuestionIcon = addQuestionButton.querySelector(".icon-add-circle");

    // Verify the action uses full-size styling and a visible icon color.
    expect(addQuestionButton.classList.contains("btn-secondary")).to.equal(true);
    expect(addQuestionButton.classList.contains("btn-mini")).to.equal(false);
    expect(addQuestionIcon.classList.contains("bg-current")).to.equal(true);
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
    getLabeledControl(element, "Question").value = "Dietary restrictions";
    getLabeledControl(element, "Question").dispatchEvent(new Event("input"));
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

    // Assert the neutral default copy is rendered.
    expect(element.textContent).to.include("Questions cannot be edited after answers have been submitted.");
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

    // Assert the warning is not rendered.
    expect(element.querySelector("[data-question-editing-warning]")).to.equal(null);
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

  it("renders distinct element ids for two editors on one page", async () => {
    // Mount two editors with the same payload name and open both modals.
    const first = await mountLitComponent("questions-editor", { name: "questions" });
    const second = await mountLitComponent("questions-editor", { name: "questions" });
    await clickButton(first, "Add question");
    await clickButton(second, "Add question");
    getLabeledControl(first, "Type").value = "single-select";
    getLabeledControl(first, "Type").dispatchEvent(new Event("change"));
    getLabeledControl(second, "Type").value = "single-select";
    getLabeledControl(second, "Type").dispatchEvent(new Event("change"));
    await first.updateComplete;
    await second.updateComplete;

    // Collect every id rendered by both editors.
    const ids = [...document.querySelectorAll("questions-editor [id]")].map((node) => node.id);

    // Verify ids are unique across the page.
    expect(ids.length).to.be.greaterThan(0);
    expect(new Set(ids).size).to.equal(ids.length);

    // Verify each label, dialog and option group points to its own editor.
    [first, second].forEach((element) => {
      [...element.querySelectorAll("label[for]")].forEach((label) => {
        expect(element.contains(document.getElementById(label.htmlFor))).to.equal(true);
      });
      [...element.querySelectorAll("[aria-labelledby]")].forEach((node) => {
        const labelledBy = document.getElementById(node.getAttribute("aria-labelledby"));
        expect(element.contains(labelledBy)).to.equal(true);
      });
      [...element.querySelectorAll("[aria-describedby]")].forEach((node) => {
        const describedBy = document.getElementById(node.getAttribute("aria-describedby"));
        expect(element.contains(describedBy)).to.equal(true);
      });
      expect(getQuestionModal(element).getAttribute("aria-labelledby")).to.equal(
        element.querySelector("h3").id,
      );
      expect(element.querySelector('[role="group"]').getAttribute("aria-labelledby")).to.not.equal(null);
      expect(element.querySelector('input[aria-label="Option 1"]').id).to.not.equal("");
    });
  });

  it("uses the element id as the id prefix when present", async () => {
    // Mount an editor with an explicit element id.
    const element = await mountLitComponentWithAttributes("questions-editor", {
      attributes: { id: "survey-questions" },
    });

    // Open the add-question modal.
    await clickButton(element, "Add question");

    // Verify the rendered ids derive from the element id.
    expect(getLabeledControl(element, "Question").id).to.equal("survey-questions-prompt");
    expect(getLabeledControl(element, "Type").id).to.equal("survey-questions-kind");
    expect(element.querySelector("h3").id).to.equal("survey-questions-modal-title");
  });

  it("renders wording from attributes", async () => {
    // Mount an editable editor with custom wording.
    const element = await mountLitComponentWithAttributes("questions-editor", {
      attributes: {
        "editing-warning": "Survey questions are locked once answers exist.",
        "empty-disabled-message": "This survey has no questions.",
        "empty-message": "Add the first survey question.",
        "required-help": "Required survey questions must be answered.",
      },
    });

    // Verify the editable empty state uses the custom copy.
    expect(element.textContent).to.include("Add the first survey question.");

    // Verify the Required help uses the custom copy.
    await clickButton(element, "Add question");
    const requiredToggle = element.querySelector('[data-question-modal] input[type="checkbox"]');
    const requiredHelp = document.getElementById(requiredToggle.getAttribute("aria-describedby"));
    expect(requiredHelp.textContent.trim()).to.equal("Required survey questions must be answered.");

    // Verify the editing warning uses the custom copy once questions exist.
    getLabeledControl(element, "Question").value = "How was the venue?";
    getLabeledControl(element, "Question").dispatchEvent(new Event("input"));
    await clickButton(element, "Add question");
    expect(element.querySelector("[data-question-editing-warning]").textContent.trim()).to.equal(
      "Survey questions are locked once answers exist.",
    );

    // Verify the disabled empty state uses the custom copy.
    element.questions = [];
    element.disabled = true;
    await element.updateComplete;
    expect(element.textContent).to.include("This survey has no questions.");
  });

  it("renders neutral empty states by default", async () => {
    // Mount an editable editor without wording attributes.
    const element = await mountLitComponent("questions-editor");

    // Verify the editable empty state.
    expect(element.textContent).to.include('No questions yet. Click "Add question" to create one.');

    // Verify the disabled empty state.
    element.disabled = true;
    await element.updateComplete;
    expect(element.textContent).to.include("No questions were added.");
  });

  it("hides the editing warning when its wording is empty", async () => {
    // Mount an editor with questions and an empty editing warning.
    const element = await mountLitComponentWithAttributes("questions-editor", {
      attributes: {
        "editing-warning": "",
        questions: JSON.stringify([buildFreeTextQuestion("00000000-0000-0000-0000-000000000101", "Venue")]),
      },
    });

    // Verify no warning is rendered.
    expect(element.querySelector("[data-question-editing-warning]")).to.equal(null);
  });

  it("applies prompt and option length limits from attributes", async () => {
    // Mount an editor with custom length limits.
    const element = await mountLitComponentWithAttributes("questions-editor", {
      attributes: {
        "option-max-length": "80",
        "prompt-max-length": "300",
      },
    });

    // Open the modal with a selectable question.
    await clickButton(element, "Add question");
    getLabeledControl(element, "Type").value = "multi-select";
    getLabeledControl(element, "Type").dispatchEvent(new Event("change"));
    await element.updateComplete;

    // Verify the inputs use the configured limits.
    expect(getLabeledControl(element, "Question").maxLength).to.equal(300);
    expect(element.querySelector('input[aria-label="Option 1"]').maxLength).to.equal(80);
  });

  it("uses default length limits when attributes are missing or invalid", async () => {
    // Mount an editor with an invalid prompt limit.
    const element = await mountLitComponentWithAttributes("questions-editor", {
      attributes: { "prompt-max-length": "invalid" },
    });

    // Open the modal with a selectable question.
    await clickButton(element, "Add question");
    getLabeledControl(element, "Type").value = "single-select";
    getLabeledControl(element, "Type").dispatchEvent(new Event("change"));
    await element.updateComplete;

    // Verify the default limits apply.
    expect(getLabeledControl(element, "Question").maxLength).to.equal(500);
    expect(element.querySelector('input[aria-label="Option 1"]').maxLength).to.equal(120);
  });

  it("disables adding questions at the max-questions limit", async () => {
    // Mount an editor one question below its limit.
    const element = await mountLitComponentWithAttributes("questions-editor", {
      attributes: {
        "max-questions": "2",
        questions: JSON.stringify([buildFreeTextQuestion("00000000-0000-0000-0000-000000000101", "Venue")]),
      },
    });

    // Verify adding is still allowed below the limit.
    expect(getAddQuestionButton(element).disabled).to.equal(false);
    expect(element.querySelector("[data-questions-limit]")).to.equal(null);

    // Add the last allowed question.
    await clickButton(element, "Add question");
    getLabeledControl(element, "Question").value = "Speakers";
    getLabeledControl(element, "Question").dispatchEvent(new Event("input"));
    await clickButton(element, "Add question");

    // Verify the add action is disabled and explained at the limit.
    const addButton = getAddQuestionButton(element);
    const limitNote = element.querySelector("[data-questions-limit]");
    expect(element.questions.length).to.equal(2);
    expect(addButton.disabled).to.equal(true);
    expect(limitNote.textContent.trim()).to.equal("You can add up to 2 questions.");
    expect(addButton.getAttribute("aria-describedby")).to.equal(limitNote.id);

    // Verify removing a question enables adding again.
    await clickButtonByLabel(element, "Delete question");
    expect(getAddQuestionButton(element).disabled).to.equal(false);
    expect(element.querySelector("[data-questions-limit]")).to.equal(null);
  });

  it("keeps registration questions unlimited without max-questions", async () => {
    // Mount an editor with many questions and no limit.
    const element = await mountLitComponent("questions-editor", {
      questions: Array.from({ length: 40 }, (_, index) =>
        buildFreeTextQuestion(`00000000-0000-0000-0000-${String(index).padStart(12, "0")}`, `Q${index}`),
      ),
    });

    // Verify adding is still allowed.
    expect(getAddQuestionButton(element).disabled).to.equal(false);
    expect(element.querySelector("[data-questions-limit]")).to.equal(null);
  });

  it("moves focus into the modal and restores it on Escape", async () => {
    // Mount an editor and focus its add action.
    const element = await mountLitComponent("questions-editor");
    const addButton = getAddQuestionButton(element);
    addButton.focus();

    // Open the modal.
    addButton.click();
    await waitForFocus(element);

    // Verify focus moves to the prompt field and the body scroll is locked.
    expect(document.activeElement).to.equal(getLabeledControl(element, "Question"));
    expect(document.body.dataset.modalOpenCount).to.equal("1");

    // Close the modal with Escape.
    document.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, key: "Escape" }));
    await waitForFocus(element);

    // Verify the modal is closed and focus returns to the trigger.
    expect(getQuestionModal(element).classList.contains("hidden")).to.equal(true);
    expect(document.activeElement).to.equal(addButton);
    expect(document.body.dataset.modalOpenCount).to.equal("0");
  });

  it("restores focus to the edit trigger when the modal closes", async () => {
    // Mount an editor with one question.
    const element = await mountLitComponent("questions-editor", {
      questions: [buildFreeTextQuestion("00000000-0000-0000-0000-000000000101", "Venue")],
    });

    // Open the modal from the edit action without focusing it first.
    const editButton = await clickButtonByLabel(element, "Edit question");
    await waitForFocus(element);
    expect(document.activeElement).to.equal(getLabeledControl(element, "Question"));

    // Cancel the edit.
    await clickButton(element, "Cancel");
    await waitForFocus(element);

    // Verify focus returns to the edit action.
    expect(document.activeElement).to.equal(editButton);
  });

  it("keeps Tab navigation inside the open modal", async () => {
    // Mount an editor and open the modal.
    const element = await mountLitComponent("questions-editor");
    await clickButton(element, "Add question");
    await waitForFocus(element);
    const modal = getQuestionModal(element);
    const saveButton = [...modal.querySelectorAll("button")].find(
      (button) => button.textContent.trim() === "Add question",
    );
    const closeButton = [...modal.querySelectorAll("button")].find(
      (button) => button.textContent.trim() === "Close modal",
    );

    // Press Tab from the last control.
    saveButton.focus();
    const forwardTab = new KeyboardEvent("keydown", { bubbles: true, cancelable: true, key: "Tab" });
    document.dispatchEvent(forwardTab);

    // Verify focus wraps to the first control.
    expect(forwardTab.defaultPrevented).to.equal(true);
    expect(document.activeElement).to.equal(closeButton);

    // Press Shift+Tab from the first control.
    const backwardTab = new KeyboardEvent("keydown", {
      bubbles: true,
      cancelable: true,
      key: "Tab",
      shiftKey: true,
    });
    document.dispatchEvent(backwardTab);

    // Verify focus wraps to the last control.
    expect(backwardTab.defaultPrevented).to.equal(true);
    expect(document.activeElement).to.equal(saveButton);
  });

  it("only binds keyboard listeners while the modal is open", async () => {
    // Mount an editor and open then close its modal.
    const element = await mountLitComponent("questions-editor");
    await clickButton(element, "Add question");
    await clickButton(element, "Cancel");

    // Press Tab while the modal is closed.
    const tab = new KeyboardEvent("keydown", { bubbles: true, cancelable: true, key: "Tab" });
    document.dispatchEvent(tab);

    // Verify the closed editor ignores the key.
    expect(tab.defaultPrevented).to.equal(false);
  });

  it("closes only the open editor on Escape", async () => {
    // Mount two editors and open the second one.
    const first = await mountLitComponent("questions-editor");
    const second = await mountLitComponent("questions-editor");
    await clickButton(second, "Add question");

    // Close it with Escape.
    document.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, key: "Escape" }));
    await second.updateComplete;

    // Verify both modals are closed and the scroll lock is released.
    expect(getQuestionModal(first).classList.contains("hidden")).to.equal(true);
    expect(getQuestionModal(second).classList.contains("hidden")).to.equal(true);
    expect(document.body.dataset.modalOpenCount).to.equal("0");
  });

  it("releases listeners and the scroll lock when removed while open", async () => {
    // Mount an editor inside a host and open the modal.
    const host = document.createElement("div");
    document.body.append(host);
    const element = document.createElement("questions-editor");
    host.append(element);
    await element.updateComplete;
    await clickButton(element, "Add question");
    expect(document.body.dataset.modalOpenCount).to.equal("1");

    // Remove the editor while the modal is open.
    element.remove();

    // Verify the scroll lock is released and keyboard listeners are removed.
    const tab = new KeyboardEvent("keydown", { bubbles: true, cancelable: true, key: "Tab" });
    document.dispatchEvent(tab);
    expect(document.body.dataset.modalOpenCount).to.equal("0");
    expect(document.body.style.overflow).to.equal("");
    expect(tab.defaultPrevented).to.equal(false);
  });
});
