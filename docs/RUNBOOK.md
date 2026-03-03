# RUNBOOK

## Objet
Runbook operationnel de BikeVoyager (local + deploiement `home`) sans donnees sensibles.

## Prerequis
- .NET SDK `10.0.x`
- Node.js `20` + npm
- Docker + Docker Compose
- PowerShell (`pwsh`) pour les scripts `scripts/dev-*`

## Local: demarrer / arreter
Demarrage (backend + frontend, et Valhalla si les donnees existent):

```powershell
./scripts/dev-up
```

Arret:

```powershell
./scripts/dev-down
```

## Local: commandes utiles
Tests agreges:

```powershell
./scripts/dev-test
```

Audit dependances:

```powershell
./scripts/dev-audit
```

Backend seul:

```powershell
dotnet run --project backend/src/BikeVoyager.Api/BikeVoyager.Api.csproj
```

Frontend seul:

```powershell
npm --prefix frontend ci
npm --prefix frontend run dev
```

AppHost (.NET Aspire):

```powershell
dotnet run --project backend/src/BikeVoyager.AppHost/BikeVoyager.AppHost.csproj
```

## Deploiement home
Pipeline de reference: [`.github/workflows/deploy-manual.yml`](../.github/workflows/deploy-manual.yml)

- Type: `workflow_dispatch` (inputs: `environment`, `ref`)
- Runner: `self-hosted`, `linux`, `ci`
- Script execute: [`scripts/deploy-home.sh`](../scripts/deploy-home.sh)
- Compose cible: [`deploy/home.compose.yml`](../deploy/home.compose.yml)

Validation post-deploiement (API + Valhalla):

```bash
curl http://127.0.0.1:5080/api/v1/health
curl http://127.0.0.1:5080/api/v1/valhalla/status
```

## Valhalla: operations
Compose local Valhalla:

```bash
docker compose -f infra/valhalla.compose.yml up -d valhalla
```

Scripts de build / update / cleanup:
- [`scripts/valhalla-build-france.ps1`](../scripts/valhalla-build-france.ps1)
- [`scripts/valhalla-check-update.ps1`](../scripts/valhalla-check-update.ps1)
- [`scripts/valhalla-watch-updates.ps1`](../scripts/valhalla-watch-updates.ps1)
- [`scripts/valhalla-cleanup.ps1`](../scripts/valhalla-cleanup.ps1)

## Configuration sensible
- Ne pas versionner de secrets dans le depot.
- Utiliser des placeholders dans `deploy/home.env` (modele: [`deploy/home.env.example`](../deploy/home.env.example)).
- Variables OAuth cloud supportees: `CloudSync__GoogleDrive__*`, `CloudSync__OneDrive__*`.
- Variables feedback SMTP supportees: `FEEDBACK__*`.

## Documentation de reference
- [README.md](../README.md)
- [docs/API.md](./API.md)
- [docs/ARCHITECTURE.md](./ARCHITECTURE.md)
- [SECURITY.md](../SECURITY.md)
