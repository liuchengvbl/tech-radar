#!/usr/bin/env node
"use strict";

const http = require("http");

const UPSTREAM_HOST = "model.mify.ai.srv";
const UPSTREAM_PORT = 80;
const LISTEN_PORT = parseInt(process.env.GLM_PROXY_PORT || "8899", 10);
const UPSTREAM_TIMEOUT = 120000;

// Models that support native web_search on mify
const WEB_SEARCH_MODELS = ["glm", "gpt"];

const WEB_SEARCH_TOOL = {
  type: "web_search",
  web_search: { enable: true, search_result: true },
};

const server = http.createServer((req, res) => {
  const chunks = [];
  req.on("data", (c) => chunks.push(c));
  req.on("end", () => {
    const rawBody = Buffer.concat(chunks).toString("utf-8");
    let outBody = rawBody;
    let toolCount = 0;
    let modelName = "";

    if (req.method === "POST" && req.url.includes("/chat/completions")) {
      try {
        const parsed = JSON.parse(rawBody);
        modelName = parsed.model || "";
        if (modelName && WEB_SEARCH_MODELS.some((m) => modelName.includes(m))) {
          if (!parsed.tools) parsed.tools = [];
          if (!parsed.tools.some((t) => t.type === "web_search")) {
            parsed.tools.unshift(WEB_SEARCH_TOOL);
          }
          toolCount = parsed.tools.length;
          outBody = JSON.stringify(parsed);
        }
      } catch (_) {}
    }

    if (toolCount > 0) {
      console.log(`[${new Date().toISOString()}] ${req.url} | model=${modelName} | web_search injected | tools=${toolCount}`);
    }

    const headers = { ...req.headers };
    headers["host"] = UPSTREAM_HOST;
    headers["content-length"] = Buffer.byteLength(outBody);
    delete headers["connection"];

    // mify uses api-key header, not Bearer authorization
    if (headers["authorization"]) {
      const key = headers["authorization"].replace(/^Bearer\s+/i, "");
      headers["api-key"] = key;
      delete headers["authorization"];
    }

    const proxyReq = http.request(
      {
        hostname: UPSTREAM_HOST,
        port: UPSTREAM_PORT,
        path: req.url,
        method: req.method,
        headers,
        timeout: UPSTREAM_TIMEOUT,
      },
      (proxyRes) => {
        res.writeHead(proxyRes.statusCode, proxyRes.headers);
        proxyRes.pipe(res);
      }
    );

    proxyReq.on("timeout", () => {
      console.error(`[${new Date().toISOString()}] upstream timeout`);
      proxyReq.destroy();
      if (!res.headersSent) {
        res.writeHead(504);
        res.end("Upstream timeout");
      }
    });

    proxyReq.on("error", (e) => {
      console.error(`[${new Date().toISOString()}] proxy error: ${e.message}`);
      if (!res.headersSent) {
        res.writeHead(502);
        res.end("Bad Gateway: " + e.message);
      }
    });

    proxyReq.write(outBody);
    proxyReq.end();
  });
});

server.listen(LISTEN_PORT, "127.0.0.1", () => {
  console.log(`[glm-websearch-proxy] listening on http://127.0.0.1:${LISTEN_PORT} -> http://${UPSTREAM_HOST}:${UPSTREAM_PORT}`);
});
