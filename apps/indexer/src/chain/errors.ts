// Which RPC errors are worth waiting for (indexer.md §4, "Live"). viem already retries every request a few
// times (clients.ts); an error that still reaches the runner after those retries is either the provider being
// down or overloaded for a while, or a problem that a retry will not fix. Only the first kind is transient.
import { HttpRequestError, LimitExceededRpcError, SocketClosedError, TimeoutError, WebSocketRequestError } from "viem";

/**
 * HTTP statuses of a provider that is overloaded or briefly down: timeout, rate limit, server and gateway errors.
 * Not 403 and 413, which viem also retries: on the providers we use they mean a refused key or a request too large
 * (a getLogs range over the provider's limit), and they come back the same at every attempt.
 */
const TRANSIENT_HTTP_STATUSES: ReadonlySet<number> = new Set([408, 429, 500, 502, 503, 504]);

/**
 * JSON-RPC codes of a rate limit sent in a 200 response: -32005 (standard "limit exceeded"), 429 (Alchemy in
 * batch mode), -32007 (QuickNode). Not -32603 ("internal error"), which anvil also returns for errors that a
 * retry does not fix: a misclassified permanent error would leave the indexer waiting forever instead of stopping.
 */
const TRANSIENT_RPC_CODES: ReadonlySet<number> = new Set([LimitExceededRpcError.code, 429, -32007]);

/** The error and its causes, outermost first: viem wraps the error of the request into the error of the action. */
function* causes(error: unknown): Generator<unknown> {
  const seen = new Set<unknown>();
  for (let current = error; current !== undefined && current !== null && !seen.has(current); ) {
    seen.add(current);
    yield current;
    current = current instanceof Error ? current.cause : undefined;
  }
}

/**
 * Whether an error is a provider that does not answer for now, so that waiting and trying again makes sense:
 * a timeout, a request that never got an HTTP response (connection refused, DNS, reset), an overloaded or
 * rate-limited provider, a closed WebSocket. Everything else is permanent for the indexer: a revert, a malformed
 * request, a reorg (ParentHashMismatchError), a DB error. The runner stops on those (indexer-roadmap step 5).
 * @param error Anything thrown by a viem call, possibly wrapped by an action error (e.g. CallExecutionError).
 */
export function isTransientRpcError(error: unknown): boolean {
  for (const cause of causes(error)) {
    if (cause instanceof TimeoutError || cause instanceof SocketClosedError || cause instanceof WebSocketRequestError) return true;
    if (cause instanceof HttpRequestError) {
      // No status: the request never got a response, i.e. the provider is unreachable.
      return cause.status === undefined || TRANSIENT_HTTP_STATUSES.has(cause.status);
    }
    if (cause instanceof Error && "code" in cause && typeof cause.code === "number" && TRANSIENT_RPC_CODES.has(cause.code)) return true;
  }
  return false;
}
