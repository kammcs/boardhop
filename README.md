# Boardhop

A mobile client for Azure DevOps Services (iOS and Android, phones and tablets) built with Flutter. It blends the Jira mobile experience for boards and work items with the GitHub mobile experience for repositories and pull request review.

Boardhop is an independent product by kammcs. It works with Azure DevOps but is not affiliated with or endorsed by Microsoft.

## Status

Discovery is complete and the stack is decided: Flutter (see [research/08-stack-comparison.md](research/08-stack-comparison.md)). The research, decisions, and spike results live in [research/](research/), starting with the [feasibility summary](research/00-feasibility-summary.md). The app scaffold has not been started yet.

## Repository layout

| Path | Contents |
|---|---|
| `research/` | Discovery documents, settled decisions, competitive research, naming |
| `research/verification/` | Anonymous probes of public Azure DevOps projects that prove API shapes |
| `research/spikes/` | Authenticated spike scripts and consolidated results against a test org |

## Running the spikes

The spike scripts take credentials only from environment variables and never store them. See [research/spikes/README.md](research/spikes/README.md).
