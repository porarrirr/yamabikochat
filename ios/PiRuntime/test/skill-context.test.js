import assert from "node:assert/strict";
import test from "node:test";

import { applyExplicitSkillInvocations } from "../src/skill-context.js";

test("formats explicit mentions with Pi Agent Core's skill invocation contract", () => {
  const request = {
    messages: [{ role: "user", content: "@review-helper check this" }],
    skillContext: {
      catalog: [{ name: "review-helper", description: "Review changes" }],
      explicitlyRequestedNames: ["review-helper"],
      explicitInstructions: ["Follow the review checklist."],
      skillFilePaths: ["/skills/review-helper/SKILL.md"],
      explicitMessageIndices: [0]
    }
  };

  const applied = applyExplicitSkillInvocations(request);

  assert.equal(request.messages[0].content, "@review-helper check this");
  assert.match(applied.messages[0].content, /^<skill name="review-helper" location="\/skills\/review-helper\/SKILL\.md">/);
  assert.match(applied.messages[0].content, /Follow the review checklist\./);
  assert.match(applied.messages[0].content, /@review-helper check this$/);
});

test("rejects incomplete explicit invocation context instead of silently skipping it", () => {
  assert.throws(
    () => applyExplicitSkillInvocations({
      messages: [{ role: "user", content: "@review-helper" }],
      skillContext: {
        explicitlyRequestedNames: ["review-helper"],
        explicitInstructions: [],
        skillFilePaths: [],
        explicitMessageIndices: []
      }
    }),
    /context is incomplete/
  );
});

test("keeps prior skill invocations in later conversation requests", () => {
  const applied = applyExplicitSkillInvocations({
    messages: [
      { role: "user", content: "@review-helper first request" },
      { role: "assistant", content: "done" },
      { role: "user", content: "continue" }
    ],
    skillContext: {
      explicitlyRequestedNames: ["review-helper"],
      explicitInstructions: ["Follow the review checklist."],
      skillFilePaths: ["/skills/review-helper/SKILL.md"],
      explicitMessageIndices: [0]
    }
  });

  assert.match(applied.messages[0].content, /^<skill name="review-helper"/);
  assert.equal(applied.messages[2].content, "continue");
});
