#!/usr/bin/env node
// Proxy de la API de Anthropic que contabiliza tokens en PokeTokenBar.
//
//   node tools/anthropic-proxy.mjs
//   export ANTHROPIC_BASE_URL=http://127.0.0.1:8318
//
// Reenvía tal cual (incluido streaming SSE) y, cuando ve el `usage` de la
// respuesta, lo reporta a POST 127.0.0.1:8317/usage.
//
// La API key viaja en las cabeceras del cliente y se reenvía sin leerse ni
// registrarse: el proxy escucha SOLO en loopback y no persiste nada.

import http from "node:http";
import https from "node:https";
import { Buffer } from "node:buffer";

const LISTEN_PORT = Number(process.env.POKETOKENBAR_PROXY_PORT ?? 8318);
const INGEST_PORT = Number(process.env.POKETOKENBAR_INGEST_PORT ?? 8317);
const UPSTREAM = process.env.ANTHROPIC_UPSTREAM ?? "https://api.anthropic.com";

function report(usage, { id, model }) {
  if (!usage) return;
  const body = JSON.stringify({ id, model, usage });
  const request = http.request(
    { host: "127.0.0.1", port: INGEST_PORT, path: "/usage", method: "POST",
      headers: { "content-type": "application/json", "content-length": Buffer.byteLength(body) } },
    (res) => res.resume()
  );
  request.on("error", (err) => console.error("[poketokenbar] ingest caído:", err.message));
  request.end(body);
}

/// El stream reparte el usage en dos eventos: `message_start` trae input y
/// cache, `message_delta` cierra con el output real. Acumulamos y reportamos
/// una vez al final, con el id del mensaje como clave de idempotencia.
function makeStreamAccumulator() {
  let buffer = "";
  const state = { id: undefined, model: undefined, usage: null };

  return {
    push(chunk) {
      buffer += chunk.toString("utf8");
      const lines = buffer.split("\n");
      buffer = lines.pop() ?? "";
      for (const line of lines) {
        if (!line.startsWith("data:")) continue;
        let payload;
        try {
          payload = JSON.parse(line.slice(5).trim());
        } catch {
          continue;
        }
        if (payload.type === "message_start" && payload.message) {
          state.id = payload.message.id;
          state.model = payload.message.model;
          state.usage = { ...(payload.message.usage ?? {}) };
        } else if (payload.usage && state.usage) {
          state.usage = { ...state.usage, ...payload.usage };
        }
      }
    },
    finish() {
      if (state.usage) report(state.usage, { id: state.id, model: state.model });
    },
  };
}

const server = http.createServer((clientRequest, clientResponse) => {
  const upstreamURL = new URL(clientRequest.url, UPSTREAM);
  const headers = { ...clientRequest.headers, host: upstreamURL.host };

  const proxied = upstreamURL;
  const transport = proxied.protocol === "https:" ? https : http;

  const upstreamRequest = transport.request(
    { hostname: proxied.hostname, port: proxied.port || (proxied.protocol === "https:" ? 443 : 80),
      path: proxied.pathname + proxied.search, method: clientRequest.method, headers },
    (upstreamResponse) => {
      clientResponse.writeHead(upstreamResponse.statusCode ?? 502, upstreamResponse.headers);

      const isStream = (upstreamResponse.headers["content-type"] ?? "").includes("text/event-stream");
      if (isStream) {
        const accumulator = makeStreamAccumulator();
        upstreamResponse.on("data", (chunk) => {
          accumulator.push(chunk);
          clientResponse.write(chunk);
        });
        upstreamResponse.on("end", () => {
          accumulator.finish();
          clientResponse.end();
        });
        return;
      }

      const chunks = [];
      upstreamResponse.on("data", (chunk) => {
        chunks.push(chunk);
        clientResponse.write(chunk);
      });
      upstreamResponse.on("end", () => {
        clientResponse.end();
        try {
          const parsed = JSON.parse(Buffer.concat(chunks).toString("utf8"));
          report(parsed.usage, { id: parsed.id, model: parsed.model });
        } catch {
          // Respuesta no-JSON (error de red, binario): nada que contabilizar.
        }
      });
    }
  );

  upstreamRequest.on("error", (err) => {
    console.error("[poketokenbar] upstream:", err.message);
    if (!clientResponse.headersSent) clientResponse.writeHead(502, { "content-type": "application/json" });
    clientResponse.end(JSON.stringify({ error: "proxy_upstream_error" }));
  });

  clientRequest.pipe(upstreamRequest);
});

server.listen(LISTEN_PORT, "127.0.0.1", () => {
  console.log(`[poketokenbar] proxy en http://127.0.0.1:${LISTEN_PORT} -> ${UPSTREAM}`);
  console.log(`[poketokenbar] reportando a http://127.0.0.1:${INGEST_PORT}/usage`);
});
