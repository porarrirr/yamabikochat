function numericStatus(value) {
  if (typeof value === "number" && Number.isInteger(value) && value >= 100 && value <= 599) {
    return value;
  }
  if (typeof value === "string" && /^\d{3}$/.test(value.trim())) {
    const parsed = Number(value);
    return parsed >= 100 && parsed <= 599 ? parsed : undefined;
  }
  return undefined;
}

function errorChain(error) {
  const values = [];
  const seen = new Set();
  let current = error;
  while (current && !seen.has(current) && values.length < 8) {
    values.push(current);
    if (typeof current !== "object" && typeof current !== "function") break;
    seen.add(current);
    current = current.cause;
  }
  return values;
}

function statusFromMessage(message) {
  const patterns = [
    /(?:^|\D)HTTP\s+(\d{3})(?:\D|$)/i,
    /(?:^|\D)status(?:\s+code)?\s*[:=]?\s*(\d{3})(?:\D|$)/i,
    /(?:^|\D)\[(\d{3})\s+[^\]]+\]/,
    /(?:^|\D)\((\d{3})\)\s*:/,
    /^\s*(?:Pi provider failed:\s*)?(\d{3})\s*:/i
  ];
  for (const pattern of patterns) {
    const match = message.match(pattern);
    const status = numericStatus(match?.[1]);
    if (status !== undefined) return status;
  }
  return undefined;
}

function codeFromMessage(message) {
  const jsonStatus = message.match(/["']status["']\s*:\s*["']([A-Z][A-Z0-9_]+)["']/i)?.[1];
  if (jsonStatus) return jsonStatus.toUpperCase();
  const named = message.match(/\b(RESOURCE_EXHAUSTED|UNAUTHENTICATED|PERMISSION_DENIED|API_KEY_INVALID)\b/i)?.[1];
  return named?.toUpperCase();
}

export function providerErrorDetails(error) {
  const chain = errorChain(error);
  const message = error instanceof Error ? error.message : String(error);
  let statusCode;
  let errorCode;

  for (const value of chain) {
    if (typeof value !== "object" || value === null) continue;
    statusCode ??= numericStatus(value.statusCode);
    statusCode ??= numericStatus(value.status);
    statusCode ??= numericStatus(value.response?.status);
    statusCode ??= numericStatus(value.$metadata?.httpStatusCode);
    errorCode ??= typeof value.providerCode === "string" ? value.providerCode : undefined;
    errorCode ??= typeof value.code === "string" ? value.code : undefined;
    errorCode ??= typeof value.error?.status === "string" ? value.error.status : undefined;
  }

  statusCode ??= statusFromMessage(message);
  errorCode ??= codeFromMessage(message);
  return {
    message,
    ...(statusCode !== undefined ? { statusCode } : {}),
    ...(errorCode ? { errorCode: errorCode.toUpperCase() } : {})
  };
}
