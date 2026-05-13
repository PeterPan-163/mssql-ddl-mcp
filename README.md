# @peterpan163/mssql-ddl-mcp

A small MCP server that exposes one tool — `ddl_query` — for running a
whitelisted set of DDL statements against a Microsoft SQL Server database.

It's designed to run **alongside** a general-purpose MSSQL MCP (such as
`@executeautomation/database-server`) to cover the DDL gap those tools
intentionally don't expose.

## What it can run

Allowed statements:

- `CREATE INDEX` (including `UNIQUE`, `NONCLUSTERED`, `CLUSTERED` variants)
- `DROP INDEX`
- `CREATE VIEW`, `CREATE OR ALTER VIEW`, `ALTER VIEW`, `DROP VIEW`

Everything else is rejected with a clear error. Patterns like `DROP TABLE`,
`TRUNCATE`, `SHUTDOWN`, `xp_*`, and `sp_executesql` are explicitly blocked.

---

## Quick install (recommended for new machines)

On any new machine, run this one PowerShell command:

```powershell
iwr -useb https://raw.githubusercontent.com/PeterPan-163/mssql-ddl-mcp/main/install.ps1 | iex
```

It checks Node.js is installed, prompts securely for the SQL password,
backs up the existing Cowork / Claude Desktop config, and adds both MCP
entries (`arcerp` for read/write and `arcerp_ddl` for whitelisted DDL).
Quit and reopen Cowork after it finishes.

Defaults (server, port, database, user) are baked into the script — edit
the `param()` block at the top before sharing if your team uses different
values.

---

## Deploying across many machines: publish once, `npx` everywhere

This is the lowest-friction path when you have multiple machines to set up.
Same pattern as `@executeautomation/database-server`: each machine just runs
`npx`, no source code copying, no per-machine builds.

### One-time, on the author machine

```powershell
# 1. (Free, one-time) Create npm account + org if you don't have them
#    https://www.npmjs.com/signup
#    https://www.npmjs.com/org/create   →  peterpan163   (free public)

# 2. Log in once on this machine
npm login

# 3. From this folder
cd C:\Users\dev\Desktop\MCP\mssql-ddl-mcp
npm install
npm run build
npm publish
```

That's it — the package is now installable globally as
`@peterpan163/mssql-ddl-mcp`.

> The npm package contains the compiled JavaScript and README — **no
> credentials, no per-customer data**. Credentials live in env vars on each
> machine's MCP config, not in the package.

### Per machine (×10)

On each of the 10 machines, edit the MCP client config and paste the
sidecar block. Node.js is the only prerequisite (already required by the
existing `arcerp_qa` MCP).

```json
{
  "mcpServers": {
    "arcerp_qa": { /* leave existing entry as-is */ },

    "arcerp_qa_ddl": {
      "command": "npx",
      "args": ["-y", "@peterpan163/mssql-ddl-mcp@0.1.1"],
      "env": {
        "MSSQL_SERVER": "<your-host>",
        "MSSQL_PORT": "1433",
        "MSSQL_DATABASE": "arcerp_qa",
        "MSSQL_USER": "mcp_ddl",
        "MSSQL_PASSWORD": "<your-mcp-ddl-password>"
      }
    }
  }
}
```

Restart the MCP client. Done — typically under a minute per machine.

> **Pin the version** (e.g. `@0.1.0`) so a future bad release doesn't roll
> out to all 10 simultaneously. Bump intentionally when you want updates.

### Updating later

```powershell
# Bump version in package.json (e.g. 0.1.0 -> 0.1.1)
npm version patch
npm publish
```

Then update the version pin on each machine when you're ready. With
`npm version patch`, npm also commits + tags in git for you.

---

## Want it private instead?

If your org policy forbids public npm, two options:

**GitHub Packages** (free for orgs): publish under your GitHub org's package
registry. Each machine needs a `.npmrc` with a personal access token.
Slightly more per-machine setup; same `npx` simplicity afterward.

**npm Pro / Teams**: $7-12/month, private scoped packages. Each machine
needs `npm login` once. Same `npx` simplicity afterward.

If you want to go this route, say the word and I'll rewrite the config for
either one.

---

## Set up a dedicated, restricted SQL login

The validator gives friendly errors, but the **real safety net** is the SQL
Server login this MCP connects as. Don't reuse the broad `dev` login — make
a new, minimal-privilege one:

```sql
USE arcerp_qa;

CREATE LOGIN mcp_ddl WITH PASSWORD = '<strong-password>';
CREATE USER mcp_ddl FOR LOGIN mcp_ddl;

-- Just enough for the whitelist
GRANT CREATE VIEW TO mcp_ddl;
GRANT ALTER ON SCHEMA::dbo TO mcp_ddl;   -- needed for CREATE/DROP INDEX

-- Explicitly do NOT grant:
--   ALTER ANY LOGIN, ALTER ANY ROLE, CONTROL SERVER,
--   db_owner, db_ddladmin (too broad — would allow DROP TABLE)
```

If this user physically can't `DROP TABLE`, a 0-day in the regex doesn't
matter. Use these `mcp_ddl` credentials in every machine's MCP config — not
the `dev` login.

---

## Smoke tests

After restart, ask the agent to run these and check the responses match:

| Test | Query | Expected |
|------|-------|----------|
| Valid | `CREATE INDEX ix_trt_status ON trt_tool_requests(status_id)` | `DDL applied successfully.` |
| Blocked | `DROP TABLE trt_tool_requests` | `Rejected: Blocked pattern: ...` |
| Not whitelisted | `CREATE PROCEDURE foo AS SELECT 1` | `Rejected: Not in DDL whitelist...` |

---

## Local development (without publishing)

If you want to iterate before publishing:

```powershell
cd C:\Users\dev\Desktop\MCP\mssql-ddl-mcp
npm install
npm run build
```

…and use the local path form on this machine only:

```json
"arcerp_qa_ddl": {
  "command": "node",
  "args": ["C:\\Users\\dev\\Desktop\\MCP\\mssql-ddl-mcp\\dist\\ddl-mcp-server.js"],
  "env": { /* … */ }
}
```

Once you're happy, `npm publish` and switch every machine to the `npx` form.

---

## What this sidecar deliberately doesn't do

- **No SELECT / INSERT / UPDATE / DELETE** — that stays with your existing
  general-purpose MSSQL MCP. Keeping concerns split limits the blast radius
  of a config typo or compromise.
- **No CREATE TABLE / ALTER TABLE** — your existing MCP's `create_table` and
  `alter_table` tools already cover those.
- **No DROP TABLE, TRUNCATE, BACKUP, RESTORE, login/role/permission changes**
  — blocked deliberately. If you ever need these, run them in SSMS where a
  human types them.
