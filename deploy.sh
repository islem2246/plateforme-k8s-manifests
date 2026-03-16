#!/bin/bash
# ============================================================
# deploy.sh — Déploiement de la Plateforme Électronique v12
# Compatible k3d et Minikube
# Changements v12 :
#   - Gateway StripPrefix=0 (path complet transmis aux services)
#   - Nginx frontend simplifié
#   - Job seed-users pour créer les utilisateurs test
# ============================================================
set -e

NAMESPACE="plateforme-electronique"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║   Plateforme Électronique de Paiement — Déploiement K8s ║"
echo "║   v12 — Eureka → DNS K8s | StripPrefix=0 | Seed Users   ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Détection du cluster
if kubectl cluster-info &>/dev/null; then
    echo -e "${GREEN}✓ Cluster Kubernetes détecté${NC}"
else
    echo -e "${RED}✗ Aucun cluster détecté. Lancez k3d ou minikube d'abord.${NC}"
    echo ""
    echo "  Pour k3d :"
    echo "    k3d cluster create plateforme --port 30180:30180@server:0 --port 30880:30880@server:0 --port 30881:30881@server:0"
    echo ""
    echo "  Pour Minikube :"
    echo "    minikube start --memory=6144 --cpus=4"
    echo "    minikube addons enable ingress"
    exit 1
fi

echo ""
echo -e "${YELLOW}[1/8] Création du namespace...${NC}"
kubectl apply -f 00-namespace/

echo -e "${YELLOW}[2/8] Déploiement des secrets et configmaps...${NC}"
kubectl apply -f 01-secrets-configmaps/

echo -e "${YELLOW}[3/8] Déploiement de l'infrastructure (PostgreSQL, Redis, Keycloak)...${NC}"
kubectl apply -f 02-infrastructure/

echo -e "${CYAN}  ⏳ Attente que PostgreSQL soit prêt...${NC}"
kubectl -n $NAMESPACE wait --for=condition=ready pod -l app=postgres --timeout=120s 2>/dev/null || echo "  ⚠ Timeout PostgreSQL — vérifiez manuellement"

echo -e "${CYAN}  ⏳ Attente que Redis soit prêt...${NC}"
kubectl -n $NAMESPACE wait --for=condition=ready pod -l app=redis --timeout=90s 2>/dev/null || echo "  ⚠ Timeout Redis"

echo -e "${CYAN}  ⏳ Attente que Keycloak soit prêt (peut prendre 2-3 min)...${NC}"
kubectl -n $NAMESPACE wait --for=condition=ready pod -l app=keycloak --timeout=300s 2>/dev/null || echo "  ⚠ Timeout Keycloak — normal au premier lancement"

echo ""
echo -e "${YELLOW}[4/8] Déploiement de l'API Gateway...${NC}"
kubectl apply -f 03-gateway/

echo -e "${YELLOW}[5/8] Déploiement des microservices métier...${NC}"
kubectl apply -f 04-services/

echo -e "${YELLOW}[6/8] Déploiement du frontend et de l'ingress...${NC}"
kubectl apply -f 05-frontend/
kubectl apply -f 06-ingress/

echo ""
echo -e "${YELLOW}[7/8] Import du realm Keycloak...${NC}"
kubectl apply -f 07-keycloak-realm/
echo -e "${CYAN}  ⏳ Le Job 'keycloak-realm-import' va s'exécuter automatiquement.${NC}"
echo -e "${CYAN}  Suivi: kubectl logs -n $NAMESPACE job/keycloak-realm-import -f${NC}"

echo ""
echo -e "${YELLOW}[8/8] Création des utilisateurs test (seed-users)...${NC}"
# Supprimer l'ancien job s'il existe
kubectl delete job seed-users -n $NAMESPACE --ignore-not-found=true 2>/dev/null
kubectl apply -f 08-post-deploy/
echo -e "${CYAN}  ⏳ Le Job 'seed-users' va enregistrer les utilisateurs via /api/auth/register.${NC}"
echo -e "${CYAN}  Suivi: kubectl logs -n $NAMESPACE job/seed-users -f${NC}"

echo ""
echo -e "${GREEN}══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ Déploiement lancé avec succès !${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${CYAN}Vérification :${NC}"
echo "  kubectl get pods -n $NAMESPACE -w"
echo ""
echo -e "${CYAN}Accès (NodePort) :${NC}"
echo "  Frontend  → http://localhost:30180"
echo "  API GW LB → port 8080 (LoadBalancer)"
echo "  Keycloak  → http://localhost:30881"
echo ""
echo -e "${CYAN}Accès (Ingress) :${NC}"
echo "  Ajoutez dans /etc/hosts : 127.0.0.1 plateforme.local"
echo "  Puis → http://plateforme.local"
echo ""
echo -e "${CYAN}Logs d'un service :${NC}"
echo "  kubectl logs -n $NAMESPACE -l app=payment-service -f"
echo ""
echo -e "${CYAN}Realm Keycloak :${NC}"
echo "  Le realm 'plateforme-electronique' est importé automatiquement."
echo "  Console admin → http://localhost:30881  (admin / admin_password)"
echo ""
echo -e "${CYAN}Utilisateurs test (créés par seed-users job) :${NC}"
echo "  admin     / admin123     (admin@plateforme.local)"
echo "  user1     / user123      (user1@plateforme.local)"
echo "  merchant1 / merchant123  (merchant1@plateforme.local)"
