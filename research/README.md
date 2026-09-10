# Research — Azure DevOps mobile app discovery

Discovery-phase research (2026-09-10) on the feasibility of a mobile app for Azure DevOps Services that blends the Jira and GitHub mobile experiences. The stack was evaluated after the initial Expo assumption and **Flutter was chosen** (document 08).

Start with **[00-feasibility-summary.md](00-feasibility-summary.md)**. It holds the verdict, the reconciled findings, the recommended architecture, phasing, and the list of spikes to run next.

| File | Scope |
|---|---|
| [00-feasibility-summary.md](00-feasibility-summary.md) | Compiled verdict and proof of viability |
| [01-api-coverage.md](01-api-coverage.md) | REST API coverage per feature area |
| [02-authentication.md](02-authentication.md) | Login, organization and tenant selection |
| [03-expo-tech-stack.md](03-expo-tech-stack.md) | Expo / React Native stack and library choices (superseded by 08b after the Flutter decision) |
| [04-competitive-landscape.md](04-competitive-landscape.md) | Competitors, GitHub and Jira benchmarks, MVP proposal |
| [05-pitfalls-and-risks.md](05-pitfalls-and-risks.md) | Risk register, policies, hard problems, deprecations |
| [06-notification-relay-and-extension.md](06-notification-relay-and-extension.md) | Push notifications via a Marketplace extension and a tenant-hosted relay |
| [07-naming-candidates.md](07-naming-candidates.md) | Brand name shortlist with conflict checks |
| [08-stack-comparison.md](08-stack-comparison.md) | Cross-platform stack comparison and recommendation (Flutter) |
| [08a-dotnet-maui-evaluation.md](08a-dotnet-maui-evaluation.md) | .NET MAUI evaluation: MSAL.NET broker, Intune SDK, UI vendors, effort |
| [08b-flutter-evaluation.md](08b-flutter-evaluation.md) | Flutter evaluation: `msal_auth`, packages, the Az DevOps competitor, ecosystem |
| [08c-react-native-and-other-stacks.md](08c-react-native-and-other-stacks.md) | React Native MSAL re-check; Kotlin Multiplatform, Capacitor, Uno, Avalonia, native, Tauri |
| [09-entra-app-registration.md](09-entra-app-registration.md) | Hand-off instructions: register Boardhop in the kammcs tenant, enable it in a customer tenant |
| [verification/](verification/) | Reproducible anonymous API probes and captured results |

Re-run the probes with:

```bash
bash research/verification/probe-public-api.sh > research/verification/probe-results.txt
```

The probes use Microsoft's public `dnceng-public` and `dnceng` projects and need no credentials. They will stop working when Azure DevOps retires public projects in 2027.
