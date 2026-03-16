#!/bin/bash
# ============================================================
# destroy.sh — Suppression complète de la plateforme
# ============================================================
set -e

NAMESPACE="plateforme-electronique"

echo "⚠️  Suppression complète du namespace '$NAMESPACE' et de toutes ses ressources..."
read -p "Confirmer ? (y/N) : " confirm

if [[ "$confirm" =~ ^[yY]$ ]]; then
    kubectl delete namespace $NAMESPACE --timeout=120s || true
    echo "✓ Namespace supprimé."
    echo ""
    echo "Pour supprimer aussi les PV orphelins :"
    echo "  kubectl get pv | grep Released | awk '{print \$1}' | xargs kubectl delete pv"
else
    echo "Annulé."
fi
