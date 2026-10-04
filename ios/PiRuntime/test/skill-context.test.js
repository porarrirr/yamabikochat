import assert from "node:assert/strict";
import test from "node:test";

import { applyExplicitSkillInvocations } from "../src/skill-context.js";

test("formats explicit mentions with Pi's skill invocation contract", () => {
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
  assert.equal(applied.messages[0].content, '<skill name="review-helper" location="/skills/review-helper/SKILL.md">\nReferences are relative to /skills/review-helper.\n\nFollow the review checklist.\n</skill>\n\n@review-helper check this');
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

test("combines explicit skills in order while preserving native attachments", () => {
  const attachments = [{ fileName: "image.png" }];
  const request = {
    messages: [{ role: "user", content: "Review", attachments }],
    skillContext: {
      explicitlyRequestedNames: ["first", "second"],
      explicitInstructions: ["First instructions", "Second instructions"],
      skillFilePaths: ["/skills/first/SKILL.md", "/skills/second/SKILL.md"],
      explicitMessageIndices: [0, 0]
    }
  };
  const applied = applyExplicitSkillInvocations(request);
  const content = applied.messages[0].content;
  assert.ok(content.indexOf('<skill name="first"') < content.indexOf('<skill name="second"'));
  assert.match(content, /References are relative to \/skills\/second\./);
  assert.match(content, /<\/skill>\n\nReview$/);
  assert.equal(applied.messages[0].attachments, attachments);
  assert.equal(request.messages[0].content, "Review");
});

test("leaves messages untouched when no skill was explicitly selected", () => {
  const request = { messages: [{ role: "user", content: "Hello" }] };
  assert.equal(applyExplicitSkillInvocations(request), request);
});
