# LazyAzure

**A Netmedia product**: made and maintained by [Netmedia](https://netmedia.agency)
(netmedia@netmedia.hr), https://github.com/netmedia/lazyazure.

The Azure infrastructure of a project, described by one map and set up, checked, changed and removed
environment by environment, with a terminal UI. Windows PowerShell 5.1 or PowerShell 7, the Azure CLI,
the GitHub CLI; no modules. This file belongs to the kit (`kit.json`); a kit update replaces it, so
project notes go into the project's own `README.md`.

**Every script explains itself**: `-Help` (or `-h`) shows its guide, modes, options and examples;
in lazyazure, `?` shows the keys of every screen.

lazyazure also comes as `lazyazure.exe`, in `infra\` and in the project's root: it starts
`infra\lazyazure.ps1` with the same arguments, in the same console (the `.ps1` is the program). From the
project's root: `.\lazyazure.exe` in PowerShell (it never runs a program from the current folder by its
name alone), `lazyazure` in cmd, or a double-click in Explorer.

```
.\infra\lazyazure.ps1 -h          .\infra\azure-setup.ps1 -h          .\infra\generate.ps1 -h
```

| Path | What | Whose |
|---|---|---|
| `infra.map.json` | **The map**: every resource of an environment and how it is named, asked, deployed, sized, priced, connected, checked and removed | the project |
| `naming.json` | The naming rules: patterns, type and environment abbreviations, the prefix, length limits | the project |
| `environments/<env>.json` | The answers of each environment (commit them; the workflows read them) | the project |
| `main.bicep` | Every Azure resource of an environment: **generated** from the map, never edited | generated |
| `azure-setup.ps1` | The setup: asks, checks, creates, removes (every change asked first); adds and removes resources of the map; starts a new project | kit |
| `lazyazure.ps1` | The terminal UI of the setup | kit |
| `generate.ps1` | Makes `main.bicep` from the map and the catalog | kit |
| `catalog/` | The kinds of resources: `<kind>.bicep` (its part of `main.bicep`), `<kind>.json` (what adding it writes into the map), `roles.json` | kit |
| `modules/` | Bicep modules the catalog uses (a Key Vault's secrets and roles, a database in its server's group) | kit |
| `route.ps1` | Which environment a workflow run deploys to (from the pushed branch) | kit |
| `kit.json` | The kit's version and its files | kit |

## A new project

Drop the empty instance into the project (`initintoproject.ps1 <project>\infra` from the LazyAzure
repository), then:

```
.\infra\lazyazure.ps1                         # New project: n
.\infra\azure-setup.ps1 -Init                 # the same without the UI
.\infra\azure-setup.ps1 -Init -SpecFile spec.json
```

It asks the project's name, the prefix of its names (`client-project`, e.g. `nm-myerp`), the region and
the name of the deployments, then its resources one by one from the catalog: what each needs (a database:
which SQL server, or a new one first), which apps use it (each gets its roles and settings), and for an
app what it uses. Then it writes the map and `naming.json` and generates `main.bicep`. Nothing in Azure
changes yet: a dry run asks the names of an environment and shows what would be created, a start creates
it.

A **spec file** answers all of it (examples/spec.example.json in the LazyAzure repository):

```json
{
  "project": { "name": "My ERP", "prefix": "nm-myerp", "region": "westeurope", "deploymentName": "myerp-{env}" },
  "resources": [
    { "kind": "appServicePlan", "key": "plan" },
    { "kind": "appService", "key": "api", "title": "ERP API", "answers": { "runtime": "DOTNETCORE|10.0" }, "requires": { "appServicePlan": "plan" } },
    { "kind": "sqlDatabase", "key": "erpDb", "requires": { "sqlServer": "new" }, "users": ["api"] },
    { "kind": "serviceBus", "key": "bus", "answers": { "queues": "invoices, mail" }, "users": ["api"], "roles": { "api": ["Azure Service Bus Data Sender"] } }
  ]
}
```

Per resource: `kind`, `key`, `title`, `answers` (its blueprint's questions), `requires` (`{kind: key}` or
`"new"`), `users` (the apps that use it), `uses` (for an app: what it uses), `roles` (`{key: [roles]}`
where a use offers roles). Anything left out takes the blueprint's default.

## Running it

Once per PC: the Azure CLI and the GitHub CLI, signed in with an account that is admin of the repository:

```
winget install Microsoft.AzureCLI GitHub.cli
gh auth login
az login                    # add --tenant <tenant> if the subscription is in another tenant
.\infra\lazyazure.ps1       # or .\infra\azure-setup.ps1 (the help, then a menu)
```

| Choice | Switch | What it does |
|---|---|---|
| Dry run | `-DryRun` | Asks every question, shows what exists and what would be created or changed. Changes and saves nothing |
| Check | `-Check` | For an environment that is set up: its saved answers, no questions; reports what is in place and what is missing. Changes nothing |
| Start | `-Start` | Asks every question, then creates and updates what is missing, each change asked first |
| Remove all | `-Remove` (`-RemoveAll`) | Deletes everything the setup created for an environment, shown first and confirmed by typing the resource group's name |
| Add a resource | `-AddResource [-Kind <kind>]` | Adds a resource of the catalog to the map with its connections, generates `main.bicep` |
| Remove a resource | `-RemoveResource [-Key <key>]` | Takes a resource out of the map with everything that refers to it, generates `main.bicep`; then offers to **delete it from Azure**: no by default, then per environment its exact name typed (and `delete prod` for production); only what the setup made, never a shared resource; an app's role assignments go first; a Key Vault's purge is asked |
| New project | `-Init [-SpecFile <file>]` | Makes the map of a new project |

More: `-Environment prod|test|stag|dev|accp`, `-RefreshToken`, `-Currency`, `-Help`. A run's steps:
answers (saved in `environments/<env>.json`), Azure resources (what-if first; deployed only on a real
change), the apps' database users (when there is SQL), GitHub -> Azure trust (OIDC), the GitHub
environment (variables, deployment tokens, deployments only from its branch), custom domains (DNS checked,
free certificates), live checks, and the next steps by hand. Every mode shows the estimated monthly cost
(Azure list prices).

A **new environment** can start from another one's answers (e.g. test from prod): the first question offers it. Names move to the new environment (`-prod` becomes `-test`, or `-test` is added); custom domains follow the same logic (`dev.app.example.com` -> `test.app.example.com`, `app.example.com` -> `app-test.example.com`); the deploy branch too (`production` -> `test`, `prod` -> `test`, `release/prod` -> `release/test`; anything else: manual runs), and a start offers to create a missing branch from the source's. Shared resources stay shared; every question is still asked, nothing is saved before the usual save.

Idempotent: a second run with the same answers changes nothing. `<` goes back to the previous question
until the first change.

## lazyazure

The same setup in one screen. **Home**: the environments, the actions, the selected environment's
resources with where each connects. **Map**: every resource in detail (role, naming, kind, Azure type, how
it is asked, checks, Bicep parameters, cost, app settings, secrets, connections), then the connections,
domains, GitHub, live checks and steps; `a` adds a resource, `x` removes the selected one. **Run**: the
steps with their progress, the resources' states, the log, and the question at the bottom (chips for
choices, toggles for several, a text field with the default). **New project** when there is no map yet.

It does none of the work: it runs `azure-setup.ps1 -Ui` (events as JSON lines out, answers in), so both
always behave the same. `-Keys` and `-Frames` drive it without a console for tests.

## The map

Each resource (in the order asked and saved) has:

| Field | Meaning |
|---|---|
| `key` | Its name in the saved answers (`names.<key>`, `groups.<key>`), in `main.bicep` and in `{key.name}` values |
| `kind` | Its catalog kind |
| `title`, `label`, `role` | How it is shown; the question; what it is for |
| `type` | The naming type (`naming.json`); `target`: the deployment target whose sub application name it carries |
| `armType` | The Azure resource type |
| `ask` | `group`, `own` (in the environment's group), `shared` (may be an existing one elsewhere, used as it is), `workspace` (Log Analytics of the `neededBy` Application Insights), `child` (a name only: a database on its server, a queue in its storage account), `name` (a name only) |
| `free`, `check` | Checks for a new name (`nameAvailable`, `vaultSoftDelete`) and for an existing resource (`linuxPlanInRegion`, `sameRegion`, `rbacVault`) |
| `param`, `groupParam` | Its `main.bicep` parameters |
| `size`, `choice`, `variants`, `when`, `optional`, `admin` | Answers asked with it, fields that depend on a choice, asked only for some answers, saved only when used |
| `tag` | A short label shown with it in lazyazure and in the questions; without one it comes from the map: a choice per environment shows its options (`shared/separate`, or the environment's answer on Home), a `when` resource `only if separate` |
| `cost` | Its row in the cost estimate (`appServicePlan`, `staticWebApp`, `pennies`, `logs`, `table`) |
| `appSettings` | An app's settings: `main.bicep` sets them, the setup checks them. `{braces}` are values of other resources: `{storage.tableEndpoint}`, `{insights.connectionString}`, `{sqlServer.host}`, `{secret.<name>}`, `{webDomain}`... |
| `secrets`, `handSecrets` | Key Vault secrets the setup keeps (`by: setup`) or that are put in by hand |
| `deploy` | An app's deploy (below, "Deploy workflows"): which folder is built how, triggered by what, published where; `generate.ps1` makes its GitHub Actions workflow |

Then `connections` (`host`, `role`, `sql`, `logs`, `telemetry`, `settings`, `deploy`, `token`),
`domains`, `github` (variables, deployment tokens, deploy roles, workflows), `live`, `cleanup`, `steps`,
`removeOrder`.

## The catalog

| Kind | What it is |
|---|---|
| `appService` | An API (or any web app) on App Service Linux; managed identity, health check, deployed with OIDC. Runtime: any Azure offers now (.NET, Node, Python, Java, PHP; default .NET 10), with a warning when its support ends within a year |
| `staticWebApp` | A front end on Static Web Apps (Free or Standard), deployed with its token |
| `functionApp` | Azure Functions: Flex Consumption (its own plan) or on an App Service plan; state in a storage account through its identity. Runtime: any Azure offers now (default .NET 10 isolated), with a warning when its support ends within a year |
| `appServicePlan` | A Linux plan (new or shared) |
| `sqlServer`, `sqlDatabase` | Azure SQL, Entra sign-in only (an admin you choose); the apps' database users are made by the step Database access (by client id, no directory rights needed; your address is let through the firewall for the step, asked first) |
| `serviceBus` | A namespace with queues, no keys; the apps get Data Sender and/or Receiver |
| `storageQueue` | A queue of a storage account; the apps get a queue role on that queue only |
| `storage` | StorageV2 without keys; the apps get the data roles you pick |
| `keyVault` | RBAC vault; the apps get Key Vault Secrets User |
| `appInsights`, `logAnalytics` | Telemetry for the apps that use it |

**Several of one kind** (two APIs, two databases): add it again; each gets its own key, parameters,
sections and sub application name (`<prefix>-api2-apiapp-<env>`); two resources of one Azure type can't
get the same name.

**A new kind**: a fragment (`catalog/<kind>.bicep`, filled per resource: `{{key}}`, `{{name}}`...), a
blueprint (`catalog/<kind>.json`: the map entry with `<placeholders>`, what it requires and creates, what
the apps that use it get) and, only for new behaviour, a handler in `azure-setup.ps1` (a name check, a
step) or `generate.ps1` (the fragment's values). Then `.\infra\generate.ps1`, a dry run, and a pull request
to LazyAzure so every project gets it.

## Naming

`{prefix}-{sub}-{type}-{env}`; Application Insights `{prefix}-{sub}-{type}-{env}-insights`, a shared one
`{prefix}-{sub}-{env}-insights`. All lowercase; the parts that are empty are left out; storage accounts
without hyphens. The sub application name belongs to a deployment target (an API, a web app, a function
app), asked for each. Types and environments are in `naming.json`.

## Deploy workflows

Each app's `deploy` in the map says **which folder, of which branch, is published where**, and
`generate.ps1` makes its workflow `.github/workflows/<workflow>` from `catalog/workflows/<kind>.yml`
(App Service .NET, Static Web App, Function app; generated files start with `# GENERATED`, never edit them,
and a workflow written by hand is never overwritten):

| Field | Meaning |
|---|---|
| `workflow`, `name`, `about` | Its file, its name in GitHub, the comment on top |
| `source` | The app's folder: a change in it triggers the deploy (`<source>/**`) |
| `paths` | More paths that trigger it (`"path"` or `{ "path", "comment" }`) |
| `everyBranch` | Triggered on every branch (its tests run everywhere); deploys still only from an environment's branch. Without it: **the environments' deploy branches** (`environments/*.json`), so a new environment's branch goes into every trigger when its answers are saved |
| `dotnet`, `project`, `publishArgs`, `test` | .NET: version, the project to publish, extra publish arguments, a test step run before |
| `node`, `build`, `app`, `api`, `tokenFallback` | Static Web App: Node version, the build step (in `source`), the built site and its functions folders, an extra token secret |
| `beforeBuild`, `afterDeploy` | The project's own steps (`{ name, id, run, workingDirectory, comment }`), e.g. a version step, a smoke test |

Where it publishes: the push's branch belongs to an environment (`route.ps1` reads `environments/*.json`), and
the workflow deploys to that environment's app: its name is the GitHub environment's variable
(`AZURE_WEBAPP_NAME`, `AZURE_<KEY>_NAME`), set by the setup. Adding an app asks its source folder and
writes its deploy; removing it deletes its workflow; saving an environment's answers regenerates the
triggers. Commit `.github/workflows` with the map.

A workflow finds the environment of a push with `route.ps1`:

```yaml
- id: route
  shell: pwsh
  run: ./infra/route.ps1 -Branch "${{ github.ref_name }}" -Chosen "${{ inputs.environment }}" >> $env:GITHUB_OUTPUT
```

and signs in to Azure with the GitHub environment's `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`,
`AZURE_SUBSCRIPTION_ID` (OIDC, `azure/login`); each app's name is a variable `AZURE_<KEY>_NAME`, a Static
Web App's token the secret `AZURE_STATIC_WEB_APPS_API_TOKEN_<KEY>`.

### Actions

Every generated workflow takes its GitHub Actions from `catalog/workflows/actions.json` by a short name
(`"checkout": "actions/checkout@v7"`): templates write `{{action:checkout}}`, a build's step `"uses": "checkout"`.
Upgrading an action there (e.g. when GitHub deprecates a Node version) upgrades every workflow on the next
`.\infra\generate.ps1`.

## Builds

Workflows of no Azure resource (build, test, pack, publish a package) go into the map's `builds`, and
`generate.ps1` writes them like the deploys (`# GENERATED`, never over a hand-written file; to move a
hand-written one into the map, describe it in `builds`, delete the file, generate and compare):

| Field | Meaning |
|---|---|
| `workflow`, `name`, `about` | Its file, its name in GitHub, the comment on top |
| `branches` | Push branches: names, and `"{environments}"` for the environments' deploy branches; none: manual runs only |
| `paths` | Paths that trigger it (the workflow itself is added) |
| `inputs` | Manual run inputs: `{ "<name>": { description, type, options, default } }` |
| `permissions` | The workflow's token permissions |
| `jobs` | `{ id, name, needs, if, runsOn, permissions, steps }` |

A step is `{ comment, name, if, id, uses, with, workingDirectory, shell, run }`; `uses` is a name of
`actions.json` or a full `owner/action@version`, `run` may have several lines.

```json
"builds": [{
  "workflow": "ci.yml", "name": "CI", "branches": ["main", "{environments}"], "paths": ["src/**"],
  "jobs": [{ "id": "test", "name": "Test", "runsOn": "ubuntu-latest", "steps": [
    { "uses": "checkout" },
    { "uses": "setup-dotnet", "with": { "dotnet-version": "10.0.x" } },
    { "name": "Test", "run": "dotnet test" } ] }]
}]
```

## Updating the kit

From the LazyAzure repository: `.\initintoproject.ps1 <project>\infra -Update`. It replaces the kit's
files (`kit.json` lists them) and never touches the project's (`infra.map.json`, `naming.json`,
`environments/`); then `.\infra\generate.ps1` shows whether `main.bicep` changes, and a dry run what that
means in Azure.

---

LazyAzure is developed by **Netmedia**  |  https://netmedia.agency  |  netmedia@netmedia.hr
