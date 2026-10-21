# LazyAzure

**A Netmedia product.** Made and maintained by [Netmedia](https://netmedia.agency)
(netmedia@netmedia.hr) for the projects Netmedia builds and runs on Azure.

A project's Azure infrastructure as **one map**, and a terminal UI that sets it up, checks it, changes it
and removes it, environment by environment.

- **The map** (`infra/infra.map.json`) says what the project has: its apps, databases, queues, vaults,
  telemetry, and how they connect (roles of managed identities, settings, telemetry, deploy roles).
- **The catalog** (`infra/catalog/`) knows how each kind is made: an API on App Service, a Static Web App,
  a function app (Flex Consumption or on a plan), SQL server and database, Service Bus, a storage queue,
  storage, Key Vault, Application Insights. Several of a kind is fine (two APIs, two databases).
- **`main.bicep` is generated** from the map, never written by hand.
- **The setup** (`azure-setup.ps1`) asks the names of an environment, compares Azure with the template
  (what-if) and creates only what is missing, each change asked first: resources, the apps' database
  users, the GitHub -> Azure trust (OIDC, no secrets), the GitHub environment, custom domains with free
  certificates, live checks; and the estimated monthly cost. Dry run, check, start, remove.
- **lazyazure** (`lazyazure.ps1`) is all of that in one screen, plus adding and removing resources and
  starting a new project.

Windows PowerShell 5.1 or PowerShell 7, the Azure CLI, the GitHub CLI. No modules.

## How to use it

Every script explains itself: run it with `-Help` (or `-h`) for its guide, modes, options and examples.

| Script | What it is for |
|---|---|
| `initintoproject.exe` / `.ps1` | (this repository) Puts the kit into a project's `infra` folder, or updates it there |
| `lazyazure.exe`, `infra\lazyazure.exe` / `.ps1` | (in the project: its root and `infra`) The terminal UI: environments, the map, runs, adding and removing resources; `?` shows the keys |
| `infra\azure-setup.ps1` | (in the project) The same without the UI: `-DryRun`, `-Check`, `-Start`, `-Remove` (`-RemoveAll`), `-AddResource`, `-RemoveResource`, `-Init` |
| `infra\generate.ps1` | (in the project) Makes `main.bicep` from the map (the setup runs it) |

**The .exe files** start the `.ps1` of the same name next to them (or in `infra\` below them), with the same
arguments, in the same console (no execution policy to think about; double-click works too). The `.ps1`
stays the program: changing it needs no new build. A project has `lazyazure.exe` in its root as well as
in `infra\`, so it starts from either. Their file properties say Netmedia, LazyAzure and the version;
`.\build-exe.ps1` rebuilds them (only after `launcher\launcher.cs` or the version changes). They aren't
code-signed, so Windows SmartScreen may ask once on a new PC.

**From the command line:** in PowerShell type `.\lazyazure.exe` (or `.\lazyazure`): PowerShell never
runs a program from the current folder by its name alone, for safety. In cmd, `lazyazure` is enough.

### 1. A new project

```
.\initintoproject.exe D:\Development\Netmedia\MyProject\infra
cd D:\Development\Netmedia\MyProject
.\lazyazure.exe                                         # New project: n
```

It asks the project's name, the prefix of its names (`client-project`, e.g. `nm-myerp`), the region, then
the resources one by one from the catalog. Or answer all of it with a spec file:
`.\infra\azure-setup.ps1 -Init -SpecFile spec.json` (`examples/spec.example.json`).

### 2. An environment in Azure

```
.\infra\azure-setup.ps1 -DryRun -Environment test     # what would be created; nothing changes
.\infra\azure-setup.ps1 -Start  -Environment test     # creates it, each change asked first
.\infra\azure-setup.ps1 -Check  -Environment test     # later: is it still as the map says?
```

Commit `infra\` afterwards (the map, `naming.json`, `main.bicep`, `environments\`): the workflows read it.

### 3. Adding a resource later

```
.\infra\azure-setup.ps1 -AddResource -Kind sqlDatabase      # or a in lazyazure
```

It asks what it needs (which SQL server, or a new one), which apps use it (each gets its database user and
a connection string without a password), writes the map and generates `main.bicep`; a dry run and a start
put it into Azure. Removing: `-RemoveResource -Key <key>` (or `x` on it in lazyazure's map).

### 4. Updating a project's kit

```
.\initintoproject.ps1 <project>\infra -Update
```

Replaces the kit's files (`infra/kit.json` lists them), keeps the project's (`infra.map.json`,
`naming.json`, `environments/`, `README.md`).

Everything else (the map's fields, the catalog, naming, workflows): [`infra/LAZYAZURE.md`](infra/LAZYAZURE.md).

## In this repository

| Path | What |
|---|---|
| `initintoproject.exe`, `initintoproject.ps1` | Puts the kit into a project, or updates it (the .exe starts the .ps1) |
| `build-exe.ps1`, `launcher/launcher.cs` | Builds the two .exe launchers |
| `infra/` | The kit: an empty instance (no map yet) |
| `infra/LAZYAZURE.md` | Everything about it: the map, the catalog, the runs, naming, workflows |
| `examples/spec.example.json` | A new project from a spec: two APIs, a web app, SQL, Service Bus, Key Vault, telemetry |

The kit is generic: nothing in it belongs to one project. A project's own files (its map, `naming.json`,
`environments/`, its README) are made in the project, by `initintoproject` and the New project questions.

---

LazyAzure is developed by **Netmedia**  ·  https://netmedia.agency  ·  netmedia@netmedia.hr
