import { expect } from "@open-wc/testing";

import "/static/js/dashboard/group/questions-editor.js";
import {
  mountLitComponent,
  mountLitComponentWithAttributes,
  useMountedElementsCleanup,
} from "/tests/unit/test-utils/lit.js";

describe("questions-editor", () => {
  useMountedElementsCleanup("questions-editor");

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

    expect(element.querySelector("#question-00000000-0000-0000-0000-000000000101")?.required).to.equal(true);
    expect(element.querySelector('input[aria-label="Option 1"]')?.required).to.equal(true);
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

    const selects = [...element.querySelectorAll("select")];

    expect(selects.map((select) => select.value)).to.deep.equal(["single-select", "multi-select"]);
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
