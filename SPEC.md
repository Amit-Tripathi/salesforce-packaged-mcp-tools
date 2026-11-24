# SPEC: MCP Apex Tools (managed 2GP)

## Goal
One managed 2GP package, built from a Partner Business Org (the Dev Hub). It gives a customer org:
1. A **packaged External Client App (ECA)** that MCP clients use for OAuth.
2. **Global `@InvocableMethod` Apex classes** that the customer admin registers as tools on a Salesforce Hosted MCP Server: an account-insights tool, plus create, read, update and delete tools for the packaged **MCP Demo** (`MCP_Demo__c`) object.

## Key constraint
Salesforce Hosted MCP docs ("Guidance for ISVs"): *ISV managed packages cannot yet include MCP server configurations.*
So `McpServerDefinition` is **not** in the package. It ships as a post-install template, `post-install/mcp/mcpServerDefinitions/AccountInsights.mcpServerDefinition-meta.xml`. The server name must be alphanumeric, 2–40 characters. The admin can deploy it or build the same server in Setup.

## Package contents (`force-app/`)
| Component | Purpose |
|---|---|
| `McpAccountInsights` (Apex, global) | Invocable action `Get Account Insights`. It takes `accountName` and returns pipeline, weighted pipeline, case counts, health, and a summary. Queries run `WITH USER_MODE`. |
| `MCP_Demo__c` (custom object + tab) | Fields: Name, `Description__c` (long text), `Status__c` (New / In Progress / Done, restricted), `Amount__c` (number 16,2), `Due_Date__c` (date). |
| `McpDemoCreate`, `McpDemoRead`, `McpDemoUpdate`, `McpDemoDelete` (Apex, global) | One `@InvocableMethod` per class (a Salesforce limit), each one MCP tool. Inputs and outputs are documented `@InvocableVariable`s. DML and queries run in `USER_MODE`. Validation and access errors come back as `success=false` + `message`, never as exceptions. Update only changes fields that are passed. Delete goes to the Recycle Bin. **Outputs are flat**: create/update return `recordId`, `name`, `description`, `status`, `amount`, `dueDate`; read returns `recordsJson` (JSON array string). The 1.0 fields `record` and `records` are kept for managed-package compatibility but are always empty. |
| `McpDemoRecord` (Apex, global) | Internal shape used to build `recordsJson`. **Never returned as a nested output.** |
| `McpDemoSupport` (Apex, public) | Shared helpers (load by Id, status validation, error text). |
| `McpAccountInsightsTest`, `McpDemoToolsTest` | Unit tests, at least 75% coverage, which `--code-coverage` requires. |
| `MCP_Tool_User` (permission set) | Apex class access for every tool, CRUD on `MCP_Demo__c`, edit access on its fields, and the tab. |
| ECA `MCP_Apex_Tools` (`ExternalClientApplication`, `ExtlClntAppOauthSettings`) | OAuth client for MCP clients. Created in the Dev Hub with distribution state `Packaged`, then retrieved. Org-side policies (`ExtlClntAppOauthConfigurablePolicies`) stay in `pbo-only/`. |

**Never packaged or committed:** `ExtlClntAppGlobalOauthSettings` (`*.ecaGlblOauth-meta.xml`), which holds the consumer key and secret. It lives in `pbo-only/` (outside the package path) and is gitignored.

## ECA OAuth settings
- Scopes: Access Salesforce hosted MCP servers (`mcp_api`, metadata token `MCP`) and Perform requests at any time (`refresh_token`, metadata token `RefreshToken`).
- PKCE required. **Issue JWT-based access tokens for named users** on (`isNamedUserJwtEnabled` in `ExtlClntAppGlobalOauthSettings`). Without it the MCP endpoint rejects tokens with `JWT Token is required`. Every other security option off.
- Callback URLs:
  - `https://claude.ai/api/mcp/auth_callback` (Claude.ai connectors)
  - `https://chatgpt.com/connector_platform_oauth_redirect` (ChatGPT connectors)
  - `http://localhost:33418/callback` (Claude Code, with a fixed `--callback-port 33418`)
  - `http://localhost:33419/callback` (Codex CLI and other local clients; verify the exact redirect path for the Codex version you use)

## Tool registration (subscriber org)
| Tool name | Apex class (API Catalog `apex-ISV_Demo__<Class>`) |
|---|---|
| `getAccountInsights` | `McpAccountInsights` |
| `createMcpDemoRecord` | `McpDemoCreate` |
| `readMcpDemoRecords` | `McpDemoRead` |
| `updateMcpDemoRecord` | `McpDemoUpdate` |
| `deleteMcpDemoRecord` | `McpDemoDelete` |

- Server URL: copy it from Setup → MCP Servers. It includes the org's My Domain: `https://api.salesforce.com/platform/mcp/v1/d/<my-domain>/<org-type>/custom/<SERVER_API_NAME>`, where org type is for example `scratch`. The `/v1/custom/…` and `/v1/sandbox/custom/…` forms from the launch blog post did not match what this org showed.
- The server starts **Inactive** after deploy. An admin must click Activate.

## Prerequisites in the Dev Hub
- Dev Hub enabled (done).
- Namespace `ISV_Demo` linked (done), and set in `sfdx-project.json`.

## Lessons
- **Invocable outputs must be flat for MCP.** In 1.0.0-1, outputs typed as a nested Apex-defined class (`McpDemoRecord`, `List<McpDemoRecord>`) passed unit tests but failed at runtime through hosted MCP ("Unexpected error while invoking tool") and the REST actions API (`Type cannot be serialized`). Adding `@AuraEnabled` didn't help. Use primitives, or a JSON string for lists. Fixed in 1.1.0.
- Verify every tool through `/services/data/vXX.0/actions/custom/apex/<ns>__<Class>` before packaging. Unit tests call Apex directly and skip that serializer.
