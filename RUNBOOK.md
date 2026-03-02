# RUNBOOK

## Objet

Ce runbook documente l'exploitation locale de BikeVoyager, avec un focus sur
Valhalla (build, mises à jour, et nettoyage disque).

## Structure du repo

- `backend/` : API .NET, AppHost Aspire, couches applicatives, tests.
- `frontend/` : application React/Vite.
- `infra/valhalla/` : données de routage, releases, logs, status.
- `scripts/` : scripts de dev et opérations (`dev-*`, `valhalla-*`).

## Solutions

- `BikeVoyager.slnx` : solution principale Visual Studio.
- `BikeVoyager.sln` : solution CLI/CI.

## Prérequis

- .NET SDK 10.x
- Node.js 20+ et npm
- Docker Desktop (nécessaire pour Valhalla)
- Dépendances frontend installées une fois : `npm ci` dans `frontend/`
- `npm ci` nécessite `package-lock.json` (présent dans le repo).

## Version image Valhalla

Pour mettre à jour Valhalla de façon reproductible, choisir un tag cible `ghcr.io/valhalla/valhalla:<tag>`, récupérer son digest via `docker buildx imagetools inspect ghcr.io/valhalla/valhalla:<tag>`, puis remplacer la référence épinglée `ghcr.io/valhalla/valhalla@sha256:...` dans `infra/valhalla.compose.yml`, `scripts/valhalla-build-france.ps1`, `scripts/valhalla-build-france.sh` et `backend/src/BikeVoyager.AppHost/AppHostBuilderExtensions.cs` (constante `ValhallaImageReference`); terminer par `docker compose -f infra/valhalla.compose.yml pull valhalla` avant de committer le bump.

## Démarrage local

```powershell
./scripts/dev-up
```

Arrêt :

```powershell
./scripts/dev-down
```

## Déploiement home

Le déploiement `home` est déclenché via GitHub Actions (`Déploiement Manuel`, mode `workflow_dispatch`) et exécute `scripts/deploy-home.sh` sur le runner self-hosted Linux. Le script met à jour `/home/arnaud/apps/bikevoyager`, puis relance `docker compose -f deploy/home.compose.yml up -d --build`.

Stack home:

- `bikevoyager-front` (port `5081`)
- `bikevoyager-api` (port `5080`)
- `bikevoyager-valhalla` (port `8002`, debug local)
- `bikevoyager-valhalla-bootstrap` (one-shot de download/build)

Le volume Docker `bikevoyager-valhalla-data` conserve les donnees Valhalla (`live/tiles`, `build-status.json`, etc.).

### Troubleshooting home

- Vérifier l'etat runtime : `docker ps --filter name=bikevoyager-api --filter name=bikevoyager-front --filter name=bikevoyager-valhalla --filter name=bikevoyager-valhalla-bootstrap`
- Suivre le bootstrap tuiles : `docker logs -f bikevoyager-valhalla-bootstrap`
- Vérifier le statut fonctionnel : `curl http://127.0.0.1:5080/api/v1/valhalla/status`
- Consulter les logs applicatifs : `docker logs --tail 120 bikevoyager-api` puis `docker logs --tail 120 bikevoyager-valhalla`
- Controler l'ecoute reseau : `ss -ltnp | grep -E '5080|5081|8002'` (ou `netstat -ltnp`)

## Démarrage F5 (Visual Studio)

1. Ouvrir `BikeVoyager.slnx`.
2. Définir `BikeVoyager.AppHost` comme projet de démarrage.
3. Lancer `F5`.

Comportement attendu :

- AppHost démarre API, frontend, Redis, et ressources Aspire.
- Dashboard Aspire disponible sur `https://localhost:17000`.
- Frontend exposé sur `http://localhost:5173` (port fixe via `VITE_DEV_PORT=5173` et `VITE_STRICT_PORT=true`).
- Watch Valhalla actif (sauf désactivation explicite).

Note :
- L'AppHost sonde `5173..5190` pour détecter une instance frontend déjà disponible.
- En démarrage standard via AppHost, le frontend est forcé sur `5173`.

## Démarrage AppHost en CLI

```powershell
dotnet run --project backend/src/BikeVoyager.AppHost/BikeVoyager.AppHost.csproj
```

## Valhalla : organisation des données

Racine données : `infra/valhalla/`

- `live/` : données actives utilisées par le service.
- `releases/candidate-*` : sorties temporaires de build.
- `releases/previous-*` : anciennes releases conservées selon rétention.
- `data/osm.pbf` : source OSM locale.
- `logs/*.log` : logs détaillées de build.
- `build-status.json` : progression build.
- `update-status.json` : statut de vérification de mise à jour.
- `.build.lock` : marqueur build en cours.

## Build Valhalla (France)

Windows :

```powershell
./scripts/valhalla-build-france.ps1
```

Linux/macOS :

```sh
chmod +x ./scripts/valhalla-build-france.sh
./scripts/valhalla-build-france.sh
```

Principes :

- Build blue/green : génération dans `releases/candidate-*`, puis promotion atomique vers `live/`.
- Tant que la promotion n'est pas terminée, l'app continue d'utiliser les anciennes tuiles `live/`.
- Rebuild relance seulement si nécessaire (données invalides, manquantes, source changée, ou forcé).

## Stratégie de mise à jour

- Vérification périodique : `scripts/valhalla-check-update.ps1` / `.sh`
- Surveillance périodique : `scripts/valhalla-watch-updates.ps1` / `.sh`
- Lancement manuel depuis l'app : `POST /api/v1/valhalla/update/start`

Par défaut recommandé :

- Détection automatique active
- Application automatique des updates désactivée
- Mise à jour lancée manuellement depuis le panneau Aide

## Nettoyage disque (important)

Script dédié :

- `scripts/valhalla-cleanup.ps1`
- `scripts/valhalla-cleanup.sh`

Ce qui est nettoyé :

- Anciennes releases `previous-*` selon rétention.
- Candidats `candidate-*` stale (orphelins/anciens).
- Logs de build anciennes (`infra/valhalla/logs/*.log`).
- Scripts temporaires `.build-step-*.sh` anciens.

Sécurité :

- Si `.build.lock` est présent, le nettoyage des releases est différé.
- Les données actives `live/` ne sont jamais ciblées par le cleanup.

Nettoyage manuel :

```powershell
./scripts/valhalla-cleanup.ps1
```

## Variables d'environnement Valhalla

Mise à jour/build :

- `VALHALLA_AUTO_BUILD`
  - `true` par défaut.
  - Auto-build uniquement si données absentes/invalides ou rebuild forcé.
- `VALHALLA_UPDATE_AUTO_BUILD`
  - `false` recommandé.
  - Si `true`, watch applique automatiquement les updates détectées.
- `VALHALLA_UPDATE_WATCH`
  - `true` par défaut.
  - Si `false`, désactive la surveillance périodique.
- `VALHALLA_UPDATE_CHECK_INTERVAL_MINUTES`
  - intervalle de vérification (défaut `180`, min `5`).
- `VALHALLA_FORCE_REBUILD`
  - force un rebuild.
- `VALHALLA_FORCE_DOWNLOAD`
  - force le retéléchargement `osm.pbf`.

Nettoyage disque :

- `VALHALLA_RELEASES_TO_KEEP`
  - nombre de `previous-*` conservés (défaut `0` pour économiser le disque).
- `VALHALLA_LOG_RETENTION_DAYS`
  - rétention des logs en jours (défaut `7`).
- `VALHALLA_STALE_CANDIDATE_HOURS`
  - suppression des `candidate-*` inactifs après N heures (défaut `6`).
- `VALHALLA_STEP_SCRIPT_RETENTION_HOURS`
  - rétention des `.build-step-*.sh` (défaut `24`).
- `VALHALLA_STALE_LOCK_MINUTES`
  - lock `.build.lock` considéré stale après N minutes (défaut `30`, min `5`).

## Endpoints utiles

Valhalla :

- `GET /api/v1/valhalla/status`
- `GET /api/v1/valhalla/ready`
- `POST /api/v1/valhalla/update/start`

Routage :

- `POST /api/v1/route`
- `POST /api/v1/loop`

## Configuration feedback (email)

### Configurer Brevo SMTP

En environnement `home`, la configuration SMTP est lue depuis
`deploy/home.env` sur la machine cible (`/home/arnaud/apps/bikevoyager/deploy/home.env`).

- Le fichier `deploy/home.env` n'est pas versionné.
- Le script `scripts/deploy-home.sh` le crée automatiquement à partir de
  `deploy/home.env.example` s'il est absent.
- Les permissions sont forcées en `600`.
- Ne jamais stocker les identifiants SMTP Brevo dans le repo ou dans les logs.

Variables attendues dans `deploy/home.env` :

- `FEEDBACK__ENABLED`
- `FEEDBACK__SENDEREMAIL` (adresse expéditeur validée dans Brevo)
- `FEEDBACK__SENDERNAME`
- `FEEDBACK__RECIPIENTEMAIL`
- `FEEDBACK__SUBJECTPREFIX`
- `FEEDBACK__SMTP__HOST` (`smtp-relay.brevo.com`)
- `FEEDBACK__SMTP__PORT` (`587`)
- `FEEDBACK__SMTP__USESSL` (`true`)
- `FEEDBACK__SMTP__USERNAME` (login SMTP Brevo)
- `FEEDBACK__SMTP__PASSWORD` (clé SMTP Brevo)

Si la configuration est absente ou incomplète, l'endpoint
`POST /api/v1/feedback` reste en `503` avec statut `disabled` (comportement
normal).

### Test rapide feedback (local docker)

```bash
curl -X POST http://127.0.0.1:5080/api/v1/feedback \
  -H "Content-Type: application/json" \
  -d '{"subject":"Retour UX mobile","message":"Le formulaire feedback fonctionne correctement depuis la page map.","contactEmail":"contact@EXAMPLE.TLD","page":"/map"}'
```

Vérification :

- Réponse HTTP `202` si l'envoi SMTP est opérationnel.
- Réponse HTTP `503` avec `status: "disabled"` si SMTP n'est pas configuré.
- Contrôler `docker logs --tail 120 bikevoyager-api` pour les erreurs SMTP.
- Vérifier la réception du mail sur `FEEDBACK__RECIPIENTEMAIL`.

## Protection API

L'API expose un garde-fou anti-abus:

- validation d'origine pour les appels `/api/v1/*` (`ApiOriginGuardMiddleware`)
- session anonyme silencieuse (`AnonymousApiSessionMiddleware`) via cookie signé HttpOnly
- rate limiting global
- rate limiting renforcé sur:
  - `/api/v1/route`
  - `/api/v1/loop`
  - `/api/v1/poi/around-route`
  - `/api/v1/export/gpx`

Paramètres `ApiSecurity` (dans `appsettings.json`):

- `AllowedOrigins`
- `GeneralRequestsPerMinute`
- `ComputeRequestsPerMinute`
- `ExportRequestsPerMinute`
- `EnforceOriginForUnsafeMethods`
- `AnonymousSessionCookieName`
- `AnonymousSessionLifetimeHours`

Comportement session anonyme:

- sur `/api/v1/*` (hors `OPTIONS`), un cookie de session est créé s'il est absent/invalide/expiré
- la partition de rate limiting utilise cette session en priorité, puis `RemoteIpAddress` en fallback
- le header `X-Forwarded-For` n'est pas utilisé directement pour la partition (anti-spoof)
- le frontend ne transmet plus `X-Session-Id`

Reverse proxy:

- pour conserver une IP client fiable derrière proxy, configurer l'infra pour ne pas exposer l'API directement et ne faire confiance qu'à des proxies réseau explicites
- sans chaîne proxy de confiance configurée, la partition fallback se fait sur l'IP de connexion vue par l'API

Note: ces protections limitent le spam mais ne remplacent pas une authentification
forte si l'API doit être exposée à des clients non fiables.

## Tests

Backend :

```powershell
dotnet test backend/tests/BikeVoyager.ApiTests/BikeVoyager.ApiTests.csproj
dotnet test backend/tests/BikeVoyager.UnitTests/BikeVoyager.UnitTests.csproj
```

Couverture API session anonyme:

- `backend/tests/BikeVoyager.ApiTests/AnonymousApiSessionTests.cs`
  - création du cookie
  - attributs de sécurité cookie
  - réutilisation sans rotation
  - remplacement d'un cookie invalide

Frontend :

```powershell
npm --prefix frontend run test
npm --prefix frontend run build
npx --prefix frontend playwright install chromium
npm --prefix frontend run e2e
```

Scripts agrégés :

```powershell
./scripts/dev-test
./scripts/dev-audit
```

## Audit UI

Passe UI documentée et auditable :

- `docs/AUDIT_TECHNIQUE.md`

## Dépannage rapide

Si un build a été coupé :

- Vérifier `infra/valhalla/.build.lock`.
- Relancer une mise à jour manuelle via l'app ou script build.
- Lancer `valhalla-cleanup` pour purger les candidats stale et vieux logs.

Si `/api/v1/loop` renvoie `422` alors que status est "ready" :

- Ce n'est pas un "Valhalla down" ; c'est une boucle non satisfaisante.
- Réessayer avec une distance/zone différente.

Si espace disque trop élevé :

- Exécuter le cleanup manuel.
- Garder `VALHALLA_RELEASES_TO_KEEP=0`.
- Réduire `VALHALLA_LOG_RETENTION_DAYS`.

