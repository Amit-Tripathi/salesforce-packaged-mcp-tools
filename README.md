# Salesforce Packaged MCP Tools

A **managed 2GP package** that turns Apex into tools that AI agents can call through a **Salesforce Hosted MCP Server**. After installing it, a customer org can connect Claude, ChatGPT, Claude Code or any MCP client to its own data. Nothing needs to be hosted outside Salesforce.

The package contains:

| Component | What it is |
|---|---|
| **External Client App** `MCP Apex Tools` | The OAuth client that MCP clients sign in with: PKCE, JWT-based access tokens, `mcp_api` and `refresh_token` scopes. |
| **MCP Demo** object (`ISV_Demo__MCP_Demo__c`) | Fields: Name, Description, Status (New / In Progress / Done), Amount, Due Date. |
| 5 invocable Apex actions | The tools: `getAccountInsights`, `createMcpDemoRecord`, `readMcpDemoRecords`, `updateMcpDemoRecord`, `deleteMcpDemoRecord`. |
| **MCP Tool User** permission set | Access to the tools, the object and its fields. |

The tools run as the signed-in user (`USER_MODE`), so sharing, object permissions and field-level security all apply. They report problems as `success=false` with a plain-language `message` instead of throwing errors.

## Install

**Current version: `1.1.0-1`** (namespace `ISV_Demo`, package version Id `04thm000004ChV7AAK`)

| Org type | Install URL |
|---|---|
| Production / Developer Edition | https://login.salesforce.com/packaging/installPackage.apexp?p0=04thm000004ChV7AAK |
| Sandbox / scratch org | https://test.salesforce.com/packaging/installPackage.apexp?p0=04thm000004ChV7AAK |

Or with the Salesforce CLI:

```bash
sf package install --package 04thm000004ChV7AAK --target-org <your-org> --wait 20
```

> Don't install `1.0.0-1` (`04thm000004ChTVAA0`): its create, read and update tools fail over MCP. Orgs on 1.0.0-1 can upgrade by installing 1.1.0-1 over it; an existing MCP server keeps working.

## Set up MCP in the installed org

1. Assign **MCP Tool User** to everyone who will call the tools.
2. Create the MCP server, using either method:
   - **Setup → Integrations → MCP Servers → New**: add the Apex Action tools *Get Account Insights* and *Create / Read / Update / Delete MCP Demo Record(s)*, **or**
   - deploy the ready-made definition from this repo:
     ```bash
     sf project deploy start --source-dir post-install/mcp --target-org <your-org>
     ```
3. **Activate** it: **Setup → MCP Servers → Account Insights → Activate**. A server stays *Inactive* after deploy, and clients can't connect until it's active. Activation takes up to about 2 minutes.
4. Copy the **Server URL** from that page. Don't build it by hand, because it includes the org's My Domain. Example: `https://api.salesforce.com/platform/mcp/v1/d/<my-domain>/scratch/custom/AccountInsights`.
5. Get the **OAuth client ID**, the External Client App's consumer key, from the package publisher. A newly installed app can take up to about 30 minutes to start accepting sign-ins.

## Connect an MCP client

- **Claude.ai**: Settings → Connectors → Add custom connector. Use the server URL, and put the consumer key in *Advanced settings → OAuth Client ID*.
- **ChatGPT**: Settings → Connectors → create a connector with the server URL, OAuth, and the consumer key as the client ID.
- **Claude Code**:
  ```bash
  claude mcp add --transport http sf-mcp-tools <SERVER_URL> --client-id <CONSUMER_KEY> --callback-port 33418
  ```
  Then run `/mcp` → *Authenticate*.
- **Codex CLI**: add the server under `[mcp_servers]` in `~/.codex/config.toml`, then run `codex mcp login`.

The External Client App allows these callback URLs: `https://claude.ai/api/mcp/auth_callback`, `https://chatgpt.com/connector_platform_oauth_redirect`, `http://localhost:33418/callback` and `http://localhost:33419/callback`.

Try: *"Create an MCP Demo record called Kickoff, amount 1200, due next Friday"*, *"Show my MCP Demo records"*, *"Mark Kickoff as Done"*, *"Delete the Kickoff record"*, *"How is the account Acme doing?"*

## Build it yourself

You need a Dev Hub (for example a Partner Business Org) with a linked namespace. Set your own namespace in `sfdx-project.json` and remove the `packageAliases` entries, which belong to the published package.

```bash
sf org login web --alias devhub --set-default-dev-hub --instance-url https://<your-devhub>.my.salesforce.com
sf org create scratch --definition-file config/project-scratch-def.json --alias mcp-scratch --duration-days 7 --set-default
sf project deploy start --source-dir force-app/main/default/objects --source-dir force-app/main/default/tabs --source-dir force-app/main/default/classes --source-dir force-app/main/default/permissionsets
sf org assign permset --name MCP_Tool_User
sf apex run test --code-coverage --result-format human --wait 10
sf package create --name "MCP Apex Tools" --package-type Managed --path force-app --target-dev-hub devhub
sf package version create --package "MCP Apex Tools" --code-coverage --installation-key-bypass --wait 30
sf package version promote --package "MCP Apex Tools@<version>"   # permanent; needed for production installs
```

**External Client App.** You can't create one in a scratch org. Create it in your Dev Hub (or deploy `force-app/main/default/externalClientApps` and `extlClntAppOauthSettings` there, with your own `contactEmail`), then retrieve it. The files committed here contain the publisher's org Ids in `orgScopedExternalApp` and `oauthLink`, so replace them with the values you retrieve. The global OAuth settings (consumer key and secret, callback URLs, PKCE, **JWT-based access tokens**) stay in the Dev Hub. Keep them in the gitignored `pbo-only/` folder, and never in the package. **This repo never contains an OAuth client ID or secret.** `scripts/check-no-oauth-secrets.sh` runs as a pre-commit hook and blocks commits that add one. Installed orgs use the Dev Hub's settings, so changing them there needs no new package version.

**Before you package a tool,** call it through the REST actions API:

```bash
sf api request rest "/services/data/v66.0/actions/custom/apex/<ns>__<Class>" --method POST --body '{"inputs":[{...}]}'
```

Hosted MCP returns tool output the same way, and it can't return nested Apex-defined types. Those fail with `Type cannot be serialized`, which unit tests don't catch. Keep tool outputs flat, or return lists as a JSON string. More detail is in [SPEC.md](SPEC.md).
