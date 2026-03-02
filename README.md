# 🚲 BikeVoyager

Application full-stack de planification d'itinéraires vélo basée sur
**.NET 10** et **React + TypeScript**.\
Déployée sur infrastructure personnelle via **runner GitHub
self-hosted**, Docker et génération automatisée des tuiles **Valhalla**.

[![CI](https://img.shields.io/github/actions/workflow/status/arnaud-wissart-lab/BikeVoyager/ci.yml?branch=main&label=CI)](https://github.com/arnaud-wissart-lab/BikeVoyager/actions/workflows/ci.yml)
[![Déploiement
manuel](https://img.shields.io/github/actions/workflow/status/arnaud-wissart-lab/BikeVoyager/deploy-manual.yml?branch=main&label=D%C3%A9ploiement%20manuel)](https://github.com/arnaud-wissart-lab/BikeVoyager/actions/workflows/deploy-manual.yml)
[![Licence](https://img.shields.io/github/license/arnaud-wissart-lab/BikeVoyager.svg?cacheSeconds=3600)](LICENSE)
![.NET 10](https://img.shields.io/badge/.NET-10-512BD4)

------------------------------------------------------------------------

## 🌍 Démo live

👉 http://bike.arnaudwissart.fr


------------------------------------------------------------------------

## 💡 Pourquoi ce projet ?

BikeVoyager démontre :

-   Orchestration complète d'un moteur de routage (**Valhalla**)
-   Génération automatisée et persistée des tuiles OSM (mode home)
-   Déploiement reproductible multi-machine (runner self-hosted +
    Docker)
-   Gestion propre d'un service externe long à initialiser (bootstrap +
    readiness + 503 contrôlé)
-   API sécurisée orientée production (Origin guard, rate limiting,
    session anonyme)
-   Stack full-stack moderne avec CI complète et tests E2E

------------------------------------------------------------------------

## 🏛 Architecture

``` mermaid
graph TD
    A[React + Vite + TypeScript] --> B[ASP.NET Core API /api/v1]
    B --> C[Valhalla Routing]
    B --> D[Overpass POI]
    B --> E[Cloud Providers OAuth]
```

------------------------------------------------------------------------

## 📸 Captures

<p align="center"> <img src="https://raw.githubusercontent.com/arnaud-wissart-lab/BikeVoyager/main/docs/screenshots/BikeVoyager1.png" width="800"/> <span width="20"></span> <img src="https://raw.githubusercontent.com/arnaud-wissart-lab/BikeVoyager/main/docs/screenshots/BikeVoyager3.png" height="400"/> </p> <p align="center"> <img src="https://raw.githubusercontent.com/arnaud-wissart-lab/BikeVoyager/main/docs/screenshots/BikeVoyager2.png" width="800"/> <span width="20"></span> <img src="https://raw.githubusercontent.com/arnaud-wissart-lab/BikeVoyager/main/docs/screenshots/BikeVoyager4.png" height="400"/></p>

------------------------------------------------------------------------

## 🔧 Stack technique

### Backend

-   ASP.NET Core (.NET 10)
-   Architecture en couches (Domain / Application / Infrastructure)
-   API versionnée `/api/v1`
-   Http Resilience (`Microsoft.Extensions.Http.Resilience`)
-   xUnit (tests unitaires + intégration)

### Frontend

-   React + Vite + TypeScript
-   i18n (FR/EN)
-   Vitest + Playwright (E2E)
-   PWA installable

### Infrastructure

-   Docker multi-services (front + api + valhalla + bootstrap)
-   Runner GitHub self-hosted Linux
-   Déploiement manuel via workflow_dispatch
-   Nginx reverse proxy (NPM)
-   Volume persistant pour les tuiles Valhalla

------------------------------------------------------------------------

## 🏗 Production (home)

Déploiement via GitHub Actions sur infrastructure personnelle.

Stack Docker : - `bikevoyager-front` - `bikevoyager-api` -
`bikevoyager-valhalla` - `bikevoyager-valhalla-bootstrap` (idempotent)

Premier déploiement : - téléchargement extract OSM France - génération
des tuiles - attente readiness (jusqu'à \~20 minutes selon machine)

Vérification :

``` bash
curl http://127.0.0.1:5080/api/v1/valhalla/status
```

### Emails (Brevo)

En environnement `home`, la configuration SMTP du module feedback se fait
sur la machine de déploiement dans `deploy/home.env` (non versionné), à
partir de `deploy/home.env.example`.

Variables requises :

- `FEEDBACK__ENABLED`
- `FEEDBACK__SENDEREMAIL` (adresse validée dans Brevo)
- `FEEDBACK__RECIPIENTEMAIL`
- `FEEDBACK__SMTP__HOST`
- `FEEDBACK__SMTP__PORT`
- `FEEDBACK__SMTP__USESSL`
- `FEEDBACK__SMTP__USERNAME`
- `FEEDBACK__SMTP__PASSWORD`

Si la configuration SMTP est incomplète (ex: host vide, sender/recipient
absents), `POST /api/v1/feedback` reste en `503` avec statut `disabled`.

------------------------------------------------------------------------

## 🔐 Protection API

-   Origin guard configurable (`ApiSecurity:AllowedOrigins`)
-   Cookie HttpOnly anonyme signé
-   Rate limiting global + endpoints de calcul renforcés
-   Validation stricte des paramètres

------------------------------------------------------------------------

## 🚀 Démarrage rapide

### Stack complète (recommandé)

``` bash
./scripts/dev-up
```

### Backend seul

``` bash
dotnet run --project backend/src/BikeVoyager.Api/BikeVoyager.Api.csproj
```

### Frontend seul

``` bash
cd frontend
npm ci
npm run dev
```

------------------------------------------------------------------------

## 🧪 Tests & Audit

``` bash
./scripts/dev-test
./scripts/dev-audit
npm --prefix frontend run test
npm --prefix frontend run e2e
```

------------------------------------------------------------------------

## 📚 Documentation

-   [Architecture](docs/ARCHITECTURE.md)
-   [API](docs/API.md)
-   [RUNBOOK](RUNBOOK.md)
-   [Audit technique](docs/AUDIT_TECHNIQUE.md)
-   [Security](SECURITY.md)
-   [Changelog](CHANGELOG.md)

------------------------------------------------------------------------

## 🎯 Objectif

BikeVoyager est un projet démonstrateur full-stack mettant l'accent sur
:

-   qualité du code
-   testabilité
-   sécurité API
-   automatisation CI/CD
-   reproductibilité en environnement personnel

Il sert de vitrine technique autour d'une stack .NET moderne orientée
production.
