#!/usr/bin/env node
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import sql from "mssql";

// ---------------------------------------------------------------------------
// DB config from environment variables
// ---------------------------------------------------------------------------
const dbConfig: sql.config = {
  server: process.env.MSSQL_SERVER ?? "",
  port: Number(process.env.MSSQL_PORT ?? 1433),
  database: process.env.MSSQL_DATABASE ?? "",
  user: process.env.MSSQL_USER ?? "",
  password: process.env.MSSQL_PASSWORD ?? "",
  options: {
    encrypt: process.env.MSSQL_ENCRYPT !== "false",
    trustServerCertificate: process.env.MSSQL_TRUST_CERT !== "false",
  },
};

// ---------------------------------------------------------------------------
// Whitelist / blocklist for DDL safety
//
// The whitelist controls which statement types this tool will execute.
// The blocklist is a belt-and-braces check: even if a statement matches the
// allowed pattern, if it contains a blocked phrase anywhere, it is rejected.
//
// REMEMBER: regex validation is approximate. The real safety net is the
// SQL Server login this MCP connects as — grant it only the permissions
// corresponding to the whitelist (see README).
// ---------------------------------------------------------------------------
const ALLOWED_DDL: RegExp[] = [
  /^\s*CREATE\s+(UNIQUE\s+)?(NONCLUSTERED\s+|CLUSTERED\s+)?INDEX\b/i,
  /^\s*DROP\s+INDEX\b/i,
  /^\s*CREATE\s+(OR\s+ALTER\s+)?VIEW\b/i,
  /^\s*ALTER\s+VIEW\b/i,
  /^\s*DROP\s+VIEW\b/i,
];

const BLOCKED: RegExp[] = [
  /\bDROP\s+TABLE\b/i,
  /\bDROP\s+DATABASE\b/i,
  /\bDROP\s+SCHEMA\b/i,
  /\bTRUNCATE\b/i,
  /\bSHUTDOWN\b/i,
  /\bxp_\w+/i, // extended stored procedures
  /\bsp_executesql\b/i, // dynamic SQL escape hatch
];

function validateDDL(q: string): { ok: boolean; reason?: string } {
  const stripped = q.trim().replace(/;\s*$/, "");
  if (!stripped) return { ok: false, reason: "Empty query" };
  if (stripped.includes(";")) {
    return { ok: false, reason: "Only one statement per call" };
  }
  for (const re of BLOCKED) {
    if (re.test(stripped)) {
      return { ok: false, reason: `Blocked pattern: ${re.source}` };
    }
  }
  if (!ALLOWED_DDL.some((re) => re.test(stripped))) {
    return {
      ok: false,
      reason:
        "Not in DDL whitelist (allowed: CREATE/DROP INDEX, CREATE/ALTER/DROP VIEW)",
    };
  }
  return { ok: true };
}

// ---------------------------------------------------------------------------
// MCP server
// ---------------------------------------------------------------------------
const server = new Server(
  { name: "mssql-ddl", version: "0.1.0" },
  { capabilities: { tools: {} } },
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "ddl_query",
      description:
        "Execute whitelisted DDL against the connected database. " +
        "Allowed: CREATE/DROP INDEX, CREATE/ALTER/DROP VIEW. " +
        "Other DDL (DROP TABLE, TRUNCATE, extended stored procs, dynamic SQL) is rejected.",
      inputSchema: {
        type: "object",
        properties: { query: { type: "string" } },
        required: ["query"],
      },
    },
  ],
}));

server.setRequestHandler(CallToolRequestSchema, async (req) => {
  if (req.params.name !== "ddl_query") {
    throw new Error(`Unknown tool: ${req.params.name}`);
  }
  const query = String(req.params.arguments?.query ?? "");
  const v = validateDDL(query);
  if (!v.ok) {
    return {
      content: [{ type: "text", text: `Rejected: ${v.reason}` }],
      isError: true,
    };
  }
  try {
    const pool = await sql.connect(dbConfig);
    try {
      await pool.request().query(query);
      return {
        content: [{ type: "text", text: "DDL applied successfully." }],
      };
    } finally {
      await pool.close();
    }
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    return {
      content: [{ type: "text", text: `DDL error: ${message}` }],
      isError: true,
    };
  }
});

await server.connect(new StdioServerTransport());
