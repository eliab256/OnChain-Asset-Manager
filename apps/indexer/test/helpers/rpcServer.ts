// A local JSON-RPC proxy for the backup-provider tests: it forwards every request to a real node (anvil) and
// lets a test replace the answer of some of them, to get a provider that is wrong in one precise way (another
// chain id, no deployless eth_call, no old state) without starting a second node.
import { createServer, type Server } from "node:http";
import type { AddressInfo } from "node:net";

export type RpcRequest = { jsonrpc: "2.0"; id: number | string; method: string; params?: unknown[] };
/** What to answer instead of the node: a result, or a JSON-RPC error. undefined forwards the request. */
export type Override = { result: unknown } | { error: { code: number; message: string } } | undefined;

export type RpcProxy = {
  /** http://127.0.0.1:<port>; any path is accepted, so a test can add a fake API key to it. */
  url: string;
  /** Methods of the requests received, in order. */
  methods: string[];
  close: () => Promise<void>;
};

/**
 * Starts the proxy on a free port of 127.0.0.1.
 * @param target The node to forward to.
 * @param override Called for every request before forwarding it.
 */
export async function startRpcProxy(target: string, override: (request: RpcRequest) => Override = () => undefined): Promise<RpcProxy> {
  const methods: string[] = [];
  const server: Server = createServer((req, res) => {
    const chunks: Buffer[] = [];
    req.on("data", (chunk: Buffer) => chunks.push(chunk));
    req.on("end", () => {
      void (async () => {
        const body = Buffer.concat(chunks).toString("utf8");
        const request = JSON.parse(body) as RpcRequest;
        methods.push(request.method);
        const replaced = override(request);
        let answer: string;
        if (replaced === undefined) {
          const response = await fetch(target, { method: "POST", headers: { "content-type": "application/json" }, body });
          answer = await response.text();
        } else {
          answer = JSON.stringify({ jsonrpc: "2.0", id: request.id, ...replaced });
        }
        res.writeHead(200, { "content-type": "application/json" }).end(answer);
      })().catch((error: unknown) => res.writeHead(500).end(String(error)));
    });
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address() as AddressInfo;
  return {
    url: `http://127.0.0.1:${port}`,
    methods,
    close: () => new Promise<void>((resolve, reject) => server.close((error) => (error === undefined ? resolve() : reject(error)))),
  };
}

/** A local port nothing listens on: the port of a server just closed. */
export async function closedPortUrl(): Promise<string> {
  const server = createServer();
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address() as AddressInfo;
  await new Promise<void>((resolve) => server.close(() => resolve()));
  return `http://127.0.0.1:${port}`;
}
