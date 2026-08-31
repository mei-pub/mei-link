const ansiControlSequence = /\u001B\[[0-?]*[ -/]*[@-~]/g;

export function cleanFrpcLogLine(line: string): string | null {
  const cleaned = line.replace(ansiControlSequence, "").trim();
  if (!cleaned) return null;
  // These are produced by our own status polling and otherwise flood the log.
  if (cleaned.includes("[http/middleware.go:") && /http (request|response):/.test(cleaned)) return null;
  return cleaned;
}

export function isFrpcLoginSuccess(line: string): boolean {
  return cleanFrpcLogLine(line)?.includes("login to server success") ?? false;
}

/** frp v0.70.0 在连接/重连失败时输出 "connect to server error: ..."（client/service.go:319）。 */
export function isFrpcConnectionFailure(line: string): boolean {
  return cleanFrpcLogLine(line)?.includes("connect to server error") ?? false;
}
