import assert from "node:assert/strict";
import test from "node:test";

import { providerErrorDetails } from "../src/provider-error.js";

test("extracts Gemini rate-limit status and code from Pi's normalized provider message", () => {
  const details = providerErrorDetails(
    new Error('Pi provider failed: 429: {"code":429,"message":"quota","status":"RESOURCE_EXHAUSTED"}')
  );

  assert.equal(details.statusCode, 429);
  assert.equal(details.errorCode, "RESOURCE_EXHAUSTED");
});

test("extracts Gemini authentication status from SDK error properties", () => {
  const error = new Error("API key not valid");
  error.status = 401;
  error.code = "UNAUTHENTICATED";

  assert.deepEqual(providerErrorDetails(error), {
    message: "API key not valid",
    statusCode: 401,
    errorCode: "UNAUTHENTICATED"
  });
});

test("does not synthesize provider metadata for unrelated failures", () => {
  assert.deepEqual(providerErrorDetails(new Error("socket closed")), { message: "socket closed" });
});
