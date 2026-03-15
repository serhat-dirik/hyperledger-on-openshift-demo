#!/usr/bin/env bash
# configure-identity-brokering.sh — Run inside a Job pod (wave 12)
# Configures central KC: OIDC Identity Brokers + Organizations + auto-idp-link flow
set -euo pipefail

CENTRAL_KC_URL="$1"
DOMAIN="$2"

KEYCLOAK_ADMIN_USER="${KEYCLOAK_ADMIN_USER:-admin}"
KEYCLOAK_ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD:-admin}"

ORGS=("techpulse" "dataforge" "neuralpath")
ORG_DISPLAY=("TechPulse Academy" "DataForge Institute" "NeuralPath Labs")

# --- Wait for central KC -----------------------------------------------
echo "==> Waiting for central KC at ${CENTRAL_KC_URL}..."
for i in $(seq 1 60); do
  if curl -sk -o /dev/null -w "%{http_code}" "${CENTRAL_KC_URL}/realms/master" | grep -q 200; then
    echo "  Central KC is ready."
    break
  fi
  echo "  Attempt $i/60 — waiting 10s..."
  sleep 10
done

# --- Wait for all org KCs -----------------------------------------------
for org in "${ORGS[@]}"; do
  ORG_KC="https://keycloak-certchain-${org}.${DOMAIN}"
  echo "==> Waiting for ${org} KC at ${ORG_KC}..."
  for i in $(seq 1 60); do
    if curl -sk -o /dev/null -w "%{http_code}" "${ORG_KC}/realms/${org}" | grep -q 200; then
      echo "  ${org} KC is ready."
      break
    fi
    echo "  Attempt $i/60 — waiting 10s..."
    sleep 10
  done
done

# --- Get admin token for central KC ------------------------------------
echo "==> Getting admin token..."
ADMIN_TOKEN=$(curl -sk -X POST "${CENTRAL_KC_URL}/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=${KEYCLOAK_ADMIN_USER}" \
  -d "password=${KEYCLOAK_ADMIN_PASSWORD}" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

if [ -z "${ADMIN_TOKEN}" ]; then
  echo "ERROR: Failed to get admin token"
  exit 1
fi

# --- Enable realm registration -----------------------------------------
echo "==> Enabling realm registration..."
curl -sk -o /dev/null -X PUT "${CENTRAL_KC_URL}/admin/realms/certchain" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"registrationAllowed": true, "registrationEmailAsUsername": true}'

# --- Create auto-idp-link flow ----------------------------------------
echo "==> Creating auto-idp-link authentication flow..."
HTTP=$(curl -sk -o /dev/null -w "%{http_code}" -X POST \
  "${CENTRAL_KC_URL}/admin/realms/certchain/authentication/flows/first%20broker%20login/copy" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"newName": "auto-idp-link"}')

if [ "${HTTP}" = "201" ]; then
  echo "  Created auto-idp-link flow."
  # Disable Review Profile and Confirm link steps
  EXECS=$(curl -sk "${CENTRAL_KC_URL}/admin/realms/certchain/authentication/flows/auto-idp-link/executions" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}")
  echo "${EXECS}" | python3 -c "
import sys, json, urllib.request, ssl
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE
execs = json.load(sys.stdin)
kc = '${CENTRAL_KC_URL}'
token = '${ADMIN_TOKEN}'
headers = {'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'}
for e in execs:
    pid = e.get('providerId', '')
    if pid in ('idp-review-profile', 'idp-confirm-link'):
        payload = json.dumps({'id': e['id'], 'requirement': 'DISABLED', 'displayName': e.get('displayName',''), 'providerId': pid}).encode()
        req = urllib.request.Request(f'{kc}/admin/realms/certchain/authentication/flows/auto-idp-link/executions',
            data=payload, headers=headers, method='PUT')
        urllib.request.urlopen(req, context=ctx)
        print(f'  Disabled {pid}')
"
elif [ "${HTTP}" = "409" ]; then
  echo "  auto-idp-link flow already exists."
fi

# --- Ensure email/profile client scopes on central KC ------------------
echo "==> Ensuring email/profile client scopes on central KC..."
EXISTING=$(curl -sk "${CENTRAL_KC_URL}/admin/realms/certchain/client-scopes" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}")

HAS_EMAIL=$(echo "${EXISTING}" | python3 -c "import sys,json; print(any(s['name']=='email' for s in json.load(sys.stdin)))")
HAS_PROFILE=$(echo "${EXISTING}" | python3 -c "import sys,json; print(any(s['name']=='profile' for s in json.load(sys.stdin)))")

if [ "${HAS_EMAIL}" = "False" ]; then
  curl -sk -o /dev/null -X POST "${CENTRAL_KC_URL}/admin/realms/certchain/client-scopes" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" -H "Content-Type: application/json" \
    -d '{"name":"email","protocol":"openid-connect","attributes":{"include.in.token.scope":"true"},"protocolMappers":[{"name":"email","protocol":"openid-connect","protocolMapper":"oidc-usermodel-attribute-mapper","config":{"user.attribute":"email","claim.name":"email","jsonType.label":"String","id.token.claim":"true","access.token.claim":"true","userinfo.token.claim":"true"}},{"name":"email verified","protocol":"openid-connect","protocolMapper":"oidc-usermodel-attribute-mapper","config":{"user.attribute":"emailVerified","claim.name":"email_verified","jsonType.label":"boolean","id.token.claim":"true","access.token.claim":"true","userinfo.token.claim":"true"}}]}'
  echo "  Created email scope."
fi
if [ "${HAS_PROFILE}" = "False" ]; then
  curl -sk -o /dev/null -X POST "${CENTRAL_KC_URL}/admin/realms/certchain/client-scopes" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" -H "Content-Type: application/json" \
    -d '{"name":"profile","protocol":"openid-connect","attributes":{"include.in.token.scope":"true"},"protocolMappers":[{"name":"username","protocol":"openid-connect","protocolMapper":"oidc-usermodel-attribute-mapper","config":{"user.attribute":"username","claim.name":"preferred_username","jsonType.label":"String","id.token.claim":"true","access.token.claim":"true","userinfo.token.claim":"true"}},{"name":"full name","protocol":"openid-connect","protocolMapper":"oidc-full-name-mapper","config":{"id.token.claim":"true","access.token.claim":"true","userinfo.token.claim":"true"}}]}'
  echo "  Created profile scope."
fi

# Assign to cert-portal and verify-api clients
for CLIENT_NAME in cert-portal verify-api; do
  CL_UUID=$(curl -sk "${CENTRAL_KC_URL}/admin/realms/certchain/clients?clientId=${CLIENT_NAME}" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" | python3 -c "import sys,json; cl=json.load(sys.stdin); print(cl[0]['id'] if cl else '')")
  [ -z "$CL_UUID" ] && continue
  for SCOPE in email profile; do
    SID=$(curl -sk "${CENTRAL_KC_URL}/admin/realms/certchain/client-scopes" \
      -H "Authorization: Bearer ${ADMIN_TOKEN}" \
      | python3 -c "import sys,json; scopes=[s for s in json.load(sys.stdin) if s['name']=='${SCOPE}']; print(scopes[0]['id'] if scopes else '')")
    [ -n "$SID" ] && curl -sk -o /dev/null -X PUT \
      "${CENTRAL_KC_URL}/admin/realms/certchain/clients/${CL_UUID}/default-client-scopes/${SID}" \
      -H "Authorization: Bearer ${ADMIN_TOKEN}"
  done
done

# --- Process each org ---------------------------------------------------
for idx in "${!ORGS[@]}"; do
  org="${ORGS[$idx]}"
  display="${ORG_DISPLAY[$idx]}"
  ORG_KC="https://keycloak-certchain-${org}.${DOMAIN}"
  SECRET="broker-secret-${org}"

  echo "==> Processing ${org}..."

  # Get org admin token
  ORG_TOKEN=$(curl -sk -X POST "${ORG_KC}/realms/master/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=admin" -d "password=admin" -d "grant_type=password" -d "client_id=admin-cli" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

  # Update broker-client redirect URIs
  BC_UUID=$(curl -sk "${ORG_KC}/admin/realms/${org}/clients?clientId=broker-client" \
    -H "Authorization: Bearer ${ORG_TOKEN}" | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['id'])")
  curl -sk -o /dev/null -X PUT "${ORG_KC}/admin/realms/${org}/clients/${BC_UUID}" \
    -H "Authorization: Bearer ${ORG_TOKEN}" -H "Content-Type: application/json" \
    -d "{\"redirectUris\":[\"${CENTRAL_KC_URL}/realms/certchain/broker/${org}/endpoint\",\"${CENTRAL_KC_URL}/realms/certchain/broker/${org}/endpoint/*\"]}"

  # Ensure email/profile scopes on org KC
  ORG_SCOPES=$(curl -sk "${ORG_KC}/admin/realms/${org}/client-scopes" -H "Authorization: Bearer ${ORG_TOKEN}")
  for SCOPE in email profile; do
    HAS=$(echo "$ORG_SCOPES" | python3 -c "import sys,json; print(any(s['name']=='${SCOPE}' for s in json.load(sys.stdin)))")
    if [ "$HAS" = "False" ]; then
      if [ "$SCOPE" = "email" ]; then
        curl -sk -o /dev/null -X POST "${ORG_KC}/admin/realms/${org}/client-scopes" \
          -H "Authorization: Bearer ${ORG_TOKEN}" -H "Content-Type: application/json" \
          -d '{"name":"email","protocol":"openid-connect","attributes":{"include.in.token.scope":"true"},"protocolMappers":[{"name":"email","protocol":"openid-connect","protocolMapper":"oidc-usermodel-attribute-mapper","config":{"user.attribute":"email","claim.name":"email","jsonType.label":"String","id.token.claim":"true","access.token.claim":"true","userinfo.token.claim":"true"}}]}'
      else
        curl -sk -o /dev/null -X POST "${ORG_KC}/admin/realms/${org}/client-scopes" \
          -H "Authorization: Bearer ${ORG_TOKEN}" -H "Content-Type: application/json" \
          -d '{"name":"profile","protocol":"openid-connect","attributes":{"include.in.token.scope":"true"},"protocolMappers":[{"name":"username","protocol":"openid-connect","protocolMapper":"oidc-usermodel-attribute-mapper","config":{"user.attribute":"username","claim.name":"preferred_username","jsonType.label":"String","id.token.claim":"true","access.token.claim":"true","userinfo.token.claim":"true"}}]}'
      fi
    fi
    SID=$(curl -sk "${ORG_KC}/admin/realms/${org}/client-scopes" -H "Authorization: Bearer ${ORG_TOKEN}" \
      | python3 -c "import sys,json; scopes=[s for s in json.load(sys.stdin) if s['name']=='${SCOPE}']; print(scopes[0]['id'] if scopes else '')")
    [ -n "$SID" ] && curl -sk -o /dev/null -X PUT \
      "${ORG_KC}/admin/realms/${org}/clients/${BC_UUID}/default-client-scopes/${SID}" \
      -H "Authorization: Bearer ${ORG_TOKEN}"
  done

  # Create IDP broker in central KC
  IDP_JSON="{
    \"alias\":\"${org}\",\"displayName\":\"${display}\",\"providerId\":\"oidc\",
    \"enabled\":true,\"trustEmail\":true,\"storeToken\":false,
    \"firstBrokerLoginFlowAlias\":\"auto-idp-link\",\"hideOnLogin\":false,
    \"config\":{
      \"clientId\":\"broker-client\",\"clientSecret\":\"${SECRET}\",
      \"tokenUrl\":\"${ORG_KC}/realms/${org}/protocol/openid-connect/token\",
      \"authorizationUrl\":\"${ORG_KC}/realms/${org}/protocol/openid-connect/auth\",
      \"logoutUrl\":\"${ORG_KC}/realms/${org}/protocol/openid-connect/logout\",
      \"userInfoUrl\":\"${ORG_KC}/realms/${org}/protocol/openid-connect/userinfo\",
      \"jwksUrl\":\"${ORG_KC}/realms/${org}/protocol/openid-connect/certs\",
      \"issuer\":\"${ORG_KC}/realms/${org}\",
      \"validateSignature\":\"true\",\"useJwksUrl\":\"true\",\"syncMode\":\"IMPORT\"
    }
  }"
  HTTP=$(curl -sk -o /dev/null -w "%{http_code}" -X POST \
    "${CENTRAL_KC_URL}/admin/realms/certchain/identity-provider/instances" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" -H "Content-Type: application/json" \
    -d "${IDP_JSON}")
  if [ "$HTTP" = "409" ]; then
    curl -sk -o /dev/null -X PUT "${CENTRAL_KC_URL}/admin/realms/certchain/identity-provider/instances/${org}" \
      -H "Authorization: Bearer ${ADMIN_TOKEN}" -H "Content-Type: application/json" -d "${IDP_JSON}"
  fi
  echo "  IDP broker: ${org} (HTTP ${HTTP})"

  # Create Organization
  ORG_JSON="{\"name\":\"${org}\",\"alias\":\"${org}\",\"enabled\":true,\"description\":\"${display}\",\"domains\":[{\"name\":\"${org}.demo\",\"verified\":true}]}"
  HTTP=$(curl -sk -o /dev/null -w "%{http_code}" -X POST \
    "${CENTRAL_KC_URL}/admin/realms/certchain/organizations" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" -H "Content-Type: application/json" \
    -d "${ORG_JSON}")
  echo "  Organization: ${org} (HTTP ${HTTP})"

  # Link IDP to Organization
  ORG_ID=$(curl -sk "${CENTRAL_KC_URL}/admin/realms/certchain/organizations?search=${org}" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" | python3 -c "import sys,json; orgs=json.load(sys.stdin); print(orgs[0]['id'] if orgs else '')")
  [ -n "$ORG_ID" ] && curl -sk -o /dev/null -X POST \
    "${CENTRAL_KC_URL}/admin/realms/certchain/organizations/${ORG_ID}/identity-providers" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" -H "Content-Type: application/json" \
    -d "\"${org}\""
done

# --- Disable Organization flow in browser auth -------------------------
echo "==> Disabling Organization browser flow..."
BROWSER_EXECS=$(curl -sk "${CENTRAL_KC_URL}/admin/realms/certchain/authentication/flows/browser/executions" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}")
ORG_EXEC_ID=$(echo "${BROWSER_EXECS}" | python3 -c "
import sys, json
for e in json.load(sys.stdin):
    if e.get('displayName') == 'Organization' and e.get('level', 99) == 0:
        print(e['id']); break
" 2>/dev/null)
if [ -n "${ORG_EXEC_ID}" ]; then
  curl -sk -o /dev/null -X PUT "${CENTRAL_KC_URL}/admin/realms/certchain/authentication/flows/browser/executions" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" -H "Content-Type: application/json" \
    -d "{\"id\":\"${ORG_EXEC_ID}\",\"requirement\":\"DISABLED\"}"
  echo "  Organization flow: DISABLED"
fi

echo "==> Identity brokering configuration complete!"
