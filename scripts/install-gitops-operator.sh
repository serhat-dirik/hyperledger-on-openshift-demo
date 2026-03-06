#!/usr/bin/env bash
# install-gitops-operator.sh — Install the OpenShift GitOps (ArgoCD) operator.
set -euo pipefail

echo "Installing OpenShift GitOps operator..."

cat <<SUBEOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-gitops-operator
  namespace: openshift-operators
spec:
  channel: latest
  installPlanApproval: Automatic
  name: openshift-gitops-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
SUBEOF

echo "Waiting for operator to be ready..."
oc wait --for=condition=Available deployment/openshift-gitops-server \
    -n openshift-gitops --timeout=300s 2>/dev/null || \
    echo "Note: Operator may take a few minutes to fully initialize."

echo "ArgoCD operator installed."
