// Secrets carried inside connection URLs. RPC providers put the API key in the URL
// (Alchemy and Infura in the path, others in the query string or as the password), and the
// database URL carries a password. Nothing here knows a specific provider: for an RPC URL every part
// after the host is treated as secret. For a database URL the path is only the database name, so it
// stays visible and is not redacted (redacting "/oam" would mangle unrelated log lines).

export type UrlKind = "rpc" | "database";

/** Path segments at least this long are also redacted on their own: an API key can show up alone. */
const KEY_LIKE_SEGMENT_LENGTH = 16;

const MASK = "***";

/**
 * The URL with only protocol, host and port visible, safe to print.
 * `https://eth-mainnet.g.alchemy.com/v2/KEY` becomes `https://eth-mainnet.g.alchemy.com/***`;
 * a URL without secrets (`http://127.0.0.1:8545`) is returned unchanged.
 * For a database URL only the password is masked: `postgresql://oam:***@localhost:5434/oam`.
 * @param raw A URL already validated by the config.
 */
export function maskUrl(raw: string, kind: UrlKind = "rpc"): string {
  const url = new URL(raw);
  if (kind === "database") {
    if (url.password !== "") url.password = MASK;
    return url.toString();
  }
  const hasUser = url.username !== "" || url.password !== "";
  const hasPath = url.pathname !== "/" && url.pathname !== "";
  const hasQuery = url.search !== "" || url.hash !== "";
  if (!hasUser && !hasPath && !hasQuery) return raw;

  const user = hasUser ? `${url.username === "" ? "" : url.username}${url.password === "" ? "" : `:${MASK}`}@` : "";
  return `${url.protocol}//${user}${url.host}${hasPath || hasQuery ? `/${MASK}` : ""}`;
}

/**
 * Substrings of the URL that must never reach a log line: password, path with query, query alone and
 * key-like path segments. Error messages (viem prints the request URL) are redacted with these.
 * For a database URL only the password.
 * @param raw A URL already validated by the config.
 */
export function urlSecrets(raw: string, kind: UrlKind = "rpc"): string[] {
  const url = new URL(raw);
  const secrets: string[] = [];
  if (url.password !== "") secrets.push(url.password);
  if (kind === "database") return secrets;
  if (url.pathname !== "/" && url.pathname !== "") secrets.push(url.pathname + url.search);
  if (url.search !== "") secrets.push(url.search);
  for (const segment of url.pathname.split("/")) {
    if (segment.length >= KEY_LIKE_SEGMENT_LENGTH) secrets.push(segment);
  }
  return secrets;
}

/**
 * Replaces every secret in `text` with ***. Longest secrets first, so a path is masked whole before
 * one of its segments.
 */
export function redact(text: string, secrets: readonly string[]): string {
  let result = text;
  for (const secret of [...secrets].sort((a, b) => b.length - a.length)) {
    if (secret !== "") result = result.split(secret).join(MASK);
  }
  return result;
}
