# Plateforme Électronique de Paiement — Kubernetes Manifests v12

## Changements v12 (par rapport à v11)

| Changement | Détail |
|---|---|
| **Gateway StripPrefix=0** | Toutes les routes transmettent le path complet (`/api/xxx/...`) aux services — plus de `StripPrefix=1` |
| **Nginx frontend simplifié** | Suppression des timeouts explicites et du cache static — config minimale et fonctionnelle |
| **Job seed-users** | Nouveau dossier `08-post-deploy/` avec un Job qui enregistre automatiquement les utilisateurs test via `/api/auth/register` |
| **Correction NodePorts** | Documentation alignée avec les manifests (30180, 30881) |

## Architecture

Microservices Spring Boot déployés sur Kubernetes (k3d / Minikube).  
**Eureka a été supprimé** et remplacé par le **DNS natif Kubernetes**.

### Composants

| Composant | Image | Port |
|-----------|-------|------|
| PostgreSQL 15 | `postgres:15-alpine` | 5432 |
| Redis 7 | `redis:7-alpine` | 6379 |
| Keycloak 22 | `quay.io/keycloak/keycloak:22.0` | 8080 |
| API Gateway | `yassmineg/plateforme_electronique_k8s-api-gateway:latest` | 8080 |
| Invoice Service | `yassmineg/plateforme-invoice-service:latest` | 8082 |
| Payment Service | `yassmineg/plateforme_electronique_k8s-payment-service:latest` | 8080 |
| Subscription Service | `yassmineg/plateforme_electronique_k8s-subscription-service:latest` | 8083 |
| Notification Service | `yassmineg/plateforme_electronique_k8s-notification-service:latest` | 8085 |
| Signature Service | `yassmineg/plateforme_electronique_k8s-signature-service:latest` | 8080 |
| User Auth Service | `yassmineg/plateforme-auth-service:latest` | 8081 |
| Frontend React | `yassmineg/plateforme-frontend:latest` | 80 |

### Structure des fichiers

```
k8s-manifests/
├── 00-namespace/          # Namespace dédié
├── 01-secrets-configmaps/ # Secrets + ConfigMaps (DB, Redis, SMTP, routes gateway)
├── 02-infrastructure/     # PostgreSQL, Redis, Keycloak
├── 03-gateway/            # API Gateway (routes DNS K8s, StripPrefix=0)
├── 04-services/           # 6 microservices métier
├── 05-frontend/           # React SPA + Nginx proxy config
├── 06-ingress/            # Ingress Traefik + NodePort + LoadBalancer
├── 07-keycloak-realm/     # Import realm Keycloak (Job)
├── 08-post-deploy/        # Seed users (Job) — enregistrement via API
├── deploy.sh              # Script de déploiement (8 étapes)
├── destroy.sh             # Script de suppression
└── README.md
```

## Prérequis

- **k3d** ou **Minikube** installé et fonctionnel
- `kubectl` configuré
- Images Docker pushées sur `yassmineg/*` DockerHub

## Déploiement rapide

### Option 1 — k3d

```bash
# Créer le cluster avec ports exposés
k3d cluster create plateforme \
  --port 30180:30180@server:0 \
  --port 30880:30880@server:0 \
  --port 30881:30881@server:0

# Déployer
chmod +x deploy.sh
./deploy.sh
```

### Option 2 — Minikube

```bash
minikube start --memory=6144 --cpus=4
minikube addons enable ingress

chmod +x deploy.sh
./deploy.sh
```

## Accès

| Service | NodePort | Ingress |
|---------|----------|---------|
| Frontend | `http://localhost:30180` | `http://plateforme.local` |
| API Gateway | LoadBalancer :8080 | `http://plateforme.local/api` |
| Keycloak | `http://localhost:30881` | `http://plateforme.local/auth` |

Pour l'ingress, ajouter dans `/etc/hosts` :
```
127.0.0.1 plateforme.local
```

## Flux de routage

```
Browser → Frontend (Nginx :80)
  ├── /api/auth/*   → user-auth-service:8080  (bypass gateway)
  ├── /api/users/*  → user-auth-service:8080  (bypass gateway)
  └── /api/*        → api-gateway:8080
                        ├── /api/invoices/**      → invoice-service:8080
                        ├── /api/payments/**      → payment-service:8080
                        ├── /api/subscriptions/** → subscription-service:8080
                        ├── /api/notifications/** → notification-service:8080
                        ├── /api/signatures/**    → signature-service:8080
                        └── /api/auth/**          → user-auth-service:8080
```

> **Note v12** : `StripPrefix=0` — les services reçoivent le path complet `/api/xxx/...`

## Utilisateurs test

Créés automatiquement par le Job `seed-users` (dossier `08-post-deploy/`) :

| Utilisateur | Email | Mot de passe |
|-------------|-------|-------------|
| admin | admin@plateforme.local | admin123 |
| user1 | user1@plateforme.local | user123 |
| merchant1 | merchant1@plateforme.local | merchant123 |

Keycloak admin console : `admin` / `admin_password`

## Changements par rapport au Docker Compose

| Avant (Docker) | Après (Kubernetes) |
|---|---|
| Eureka Server pour service discovery | DNS Kubernetes natif (`<service>.<namespace>.svc.cluster.local`) |
| `depends_on` Docker Compose | `initContainers` avec `busybox` (wait-for-*) |
| Docker volumes | PersistentVolumeClaims |
| Docker bridge network | Kubernetes ClusterIP Services |
| Ports exposés sur le host | NodePort + Ingress + LoadBalancer |
| Variables en dur / .env | Secrets + ConfigMaps |
| Single instance | HPA sur Payment Service (scalable ×N) |
| Création manuelle des users | Job `seed-users` automatique |

## Vérification post-déploiement

```bash
# Statut des pods
kubectl get pods -n plateforme-electronique

# Logs du seed-users
kubectl logs -n plateforme-electronique job/seed-users

# Logs du realm import
kubectl logs -n plateforme-electronique job/keycloak-realm-import

# Test login manuel
kubectl run -n plateforme-electronique test-login --rm -it \
  --image=curlimages/curl:8.5.0 --restart=Never -- \
  curl -s -X POST http://frontend:80/api/auth/login \
    -H "Content-Type: application/json" \
    -d '{"email":"admin@plateforme.local","password":"admin123"}'
```

## Suppression

```bash
chmod +x destroy.sh
./destroy.sh
```

## Push vers un repo Git (pour ArgoCD)

```bash
cd k8s-manifests
git init
git add .
git commit -m "feat: K8s manifests v12 - StripPrefix=0, seed-users job"
git remote add origin https://github.com/yassmineg/plateforme-k8s-manifests.git
git push -u origin main
```
