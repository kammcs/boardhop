# Boardhop

Push notifications for [Boardhop](https://github.com/kammcs/boardhop), the mobile client for Azure DevOps Services.

Azure DevOps has no notification inbox API and no push channel. Service hooks are the only real-time
feed, and creating them means a project administrator clicking through fourteen dialogs per project.
This extension does that work: it adds a **Boardhop** page to **Organization settings** and to every
project's **Project settings**, where an administrator connects the organization to the Boardhop relay
and creates, repairs or removes the relay's subscriptions one project at a time, or all at once.

## What the page does

- **Relay URL** — where the hooks post. Stored once for the whole organization, in this extension's
  own data store, so the mobile app can find the relay after sign-in.
- **Organization key** — the credential the relay checks on every delivery. Ask kammcs for it. It is
  typed in when you act and is **never stored** by the extension: not in the data store, not in the
  browser.
- **Check connection** — asks the relay how many subscriptions it has for this organization.
- **Enable / Repair / Remove** per project — creates the fourteen subscriptions, deletes the broken or
  duplicated ones and re-creates them, or takes them all away again. Each project's row shows how many
  of the fourteen exist in Azure DevOps, the worst subscription status Azure DevOps reports
  (`enabled`, `onProbation`, `disabledBySystem`, `disabledByUser`, `disabledByInactiveIdentity`) and
  how many the relay has registered.

The fourteen subscriptions cover pull requests (created, pushed to, reviewers changed, status changed,
voted on, commented on, failed to merge), work items (created, updated, commented on), builds, pipeline
run states and the two pipeline approval events.

## What the administrator needs

- A **Project Collection Administrator** installs the extension for the organization.
- A **project administrator** of each project creates that project's hooks. If you are not one, the
  page says so on that project's row and carries on with the others.
- An **organization key** from kammcs. One key per organization; it is set on the relay before you start.

## What leaves the tenant

With the shared relay, hook metadata leaves the organization and lands on the kammcs relay: ids, links,
event types and sometimes a title. **Comments, descriptions and code never do.** Notifications are
enriched on the phone with the signed-in user's own token, so the body of a work item, pull request or
comment is fetched from Azure DevOps by that user and never passes through the relay, Apple or Google.
The relay stores only subscription ids, event types, the routing label and the project name and id.

The relay is open in this repository: <https://github.com/kammcs/boardhop/blob/main/relay/README.md>.

## Permissions

The extension asks for **project and team (read)**, **service hooks (read and write)** and
**extension data (read and write)**. It creates and deletes only subscriptions whose delivery URL is
the relay's own `…/hooks/{organization}` endpoint; it never touches a subscription created by anyone else.
