#!/usr/bin/env bash
# ============================================================================
# Configure Central Keycloak – Identity Brokering + Organizations
# ============================================================================
# Run AFTER all 4 KC instances are deployed and healthy.
# Discovers Route URLs, creates OIDC Identity Brokers in central KC,
# creates Organizations with email-domain-based IDP routing.
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../env.sh"

# Keycloak admin credentials (defaults match realm-import bootstrap)
KEYCLOAK_ADMIN_USER="${KEYCLOAK_ADMIN_USER:-admin}"
KEYCLOAK_ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD:-admin}"

# --- Discover Route URLs ---------------------------------------------------
echo "==> Discovering Keycloak Route URLs..."

CENTRAL_KC_URL="https://$(oc get route keycloak -n certchain -o jsonpath='{.spec.host}')"
TP_KC_URL="https://$(oc get route keycloak -n certchain-techpulse -o jsonpath='{.spec.host}')"
DF_KC_URL="https://$(oc get route keycloak -n certchain-dataforge -o jsonpath='{.spec.host}')"
NP_KC_URL="https://$(oc get route keycloak -n certchain-neuralpath -o jsonpath='{.spec.host}')"

echo "  Central KC: ${CENTRAL_KC_URL}"
echo "  TechPulse KC: ${TP_KC_URL}"
echo "  DataForge KC: ${DF_KC_URL}"
echo "  NeuralPath KC: ${NP_KC_URL}"

# --- Get admin token for central KC ----------------------------------------
echo "==> Getting admin token for central KC..."
ADMIN_TOKEN=$(curl -s -X POST "${CENTRAL_KC_URL}/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=${KEYCLOAK_ADMIN_USER}" \
  -d "password=${KEYCLOAK_ADMIN_PASSWORD}" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

if [ -z "${ADMIN_TOKEN}" ]; then
  echo "ERROR: Failed to get admin token from central KC"
  exit 1
fi
echo "  Got admin token."

# --- Helper: update redirect URIs on org KC broker-client -------------------
update_org_broker_redirect() {
  local ORG_KC_URL=$1
  local ORG_REALM=$2
  local ORG_SECRET=$3

  echo "  Updating broker-client redirect URIs on ${ORG_REALM} KC..."
  local ORG_ADMIN_TOKEN
  ORG_ADMIN_TOKEN=$(curl -s -X POST "${ORG_KC_URL}/realms/master/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=${KEYCLOAK_ADMIN_USER}" \
    -d "password=${KEYCLOAK_ADMIN_PASSWORD}" \
    -d "grant_type=password" \
    -d "client_id=admin-cli" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

  # Get broker-client ID
  local CLIENT_ID
  CLIENT_ID=$(curl -s "${ORG_KC_URL}/admin/realms/${ORG_REALM}/clients?clientId=broker-client" \
    -H "Authorization: Bearer ${ORG_ADMIN_TOKEN}" | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['id'])")

  # Update redirect URIs to include exact central KC callback URL
  curl -s -X PUT "${ORG_KC_URL}/admin/realms/${ORG_REALM}/clients/${CLIENT_ID}" \
    -H "Authorization: Bearer ${ORG_ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
      \"redirectUris\": [
        \"${CENTRAL_KC_URL}/realms/certchain/broker/${ORG_REALM}/endpoint\",
        \"${CENTRAL_KC_URL}/realms/certchain/broker/${ORG_REALM}/endpoint/*\"
      ]
    }"
}

# --- Helper: ensure email/profile client scopes exist on org KC ------------
# KC realm import only creates scopes explicitly defined in the clientScopes
# array. The standard OIDC scopes (email, profile) must be created manually
# if missing, otherwise broker tokens won't include email claims and the
# auto-idp-link flow will fail with "Email is null".
ensure_org_client_scopes() {
  local ORG_KC_URL=$1
  local ORG_REALM=$2

  echo "  Ensuring email/profile client scopes exist on ${ORG_REALM} KC..."
  local ORG_ADMIN_TOKEN
  ORG_ADMIN_TOKEN=$(curl -s -X POST "${ORG_KC_URL}/realms/master/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=${KEYCLOAK_ADMIN_USER}" \
    -d "password=${KEYCLOAK_ADMIN_PASSWORD}" \
    -d "grant_type=password" \
    -d "client_id=admin-cli" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

  local CLIENT_UUID
  CLIENT_UUID=$(curl -s "${ORG_KC_URL}/admin/realms/${ORG_REALM}/clients?clientId=broker-client" \
    -H "Authorization: Bearer ${ORG_ADMIN_TOKEN}" | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['id'])")

  # Check if 'email' scope already exists
  local EXISTING_SCOPES
  EXISTING_SCOPES=$(curl -s "${ORG_KC_URL}/admin/realms/${ORG_REALM}/client-scopes" \
    -H "Authorization: Bearer ${ORG_ADMIN_TOKEN}")

  local HAS_EMAIL HAS_PROFILE
  HAS_EMAIL=$(echo "${EXISTING_SCOPES}" | python3 -c "import sys,json; print(any(s['name']=='email' for s in json.load(sys.stdin)))")
  HAS_PROFILE=$(echo "${EXISTING_SCOPES}" | python3 -c "import sys,json; print(any(s['name']=='profile' for s in json.load(sys.stdin)))")

  if [ "${HAS_EMAIL}" = "False" ]; then
    echo "    Creating 'email' client scope with mappers..."
    curl -s -o /dev/null -X POST "${ORG_KC_URL}/admin/realms/${ORG_REALM}/client-scopes" \
      -H "Authorization: Bearer ${ORG_ADMIN_TOKEN}" \
      -H "Content-Type: application/json" \
      -d '{
        "name":"email","description":"OpenID Connect built-in scope: email",
        "protocol":"openid-connect",
        "attributes":{"include.in.token.scope":"true","display.on.consent.screen":"true"},
        "protocolMappers":[
          {"name":"email","protocol":"openid-connect","protocolMapper":"oidc-usermodel-attribute-mapper",
           "config":{"user.attribute":"email","claim.name":"email","jsonType.label":"String",
                     "id.token.claim":"true","access.token.claim":"true","userinfo.token.claim":"true"}},
          {"name":"email verified","protocol":"openid-connect","protocolMapper":"oidc-usermodel-attribute-mapper",
           "config":{"user.attribute":"emailVerified","claim.name":"email_verified","jsonType.label":"boolean",
                     "id.token.claim":"true","access.token.claim":"true","userinfo.token.claim":"true"}}
        ]}'
  fi

  if [ "${HAS_PROFILE}" = "False" ]; then
    echo "    Creating 'profile' client scope with mappers..."
    curl -s -o /dev/null -X POST "${ORG_KC_URL}/admin/realms/${ORG_REALM}/client-scopes" \
      -H "Authorization: Bearer ${ORG_ADMIN_TOKEN}" \
      -H "Content-Type: application/json" \
      -d '{
        "name":"profile","description":"OpenID Connect built-in scope: profile",
        "protocol":"openid-connect",
        "attributes":{"include.in.token.scope":"true","display.on.consent.screen":"true"},
        "protocolMappers":[
          {"name":"username","protocol":"openid-connect","protocolMapper":"oidc-usermodel-attribute-mapper",
           "config":{"user.attribute":"username","claim.name":"preferred_username","jsonType.label":"String",
                     "id.token.claim":"true","access.token.claim":"true","userinfo.token.claim":"true"}},
          {"name":"full name","protocol":"openid-connect","protocolMapper":"oidc-full-name-mapper",
           "config":{"id.token.claim":"true","access.token.claim":"true","userinfo.token.claim":"true"}},
          {"name":"given name","protocol":"openid-connect","protocolMapper":"oidc-usermodel-attribute-mapper",
           "config":{"user.attribute":"firstName","claim.name":"given_name","jsonType.label":"String",
                     "id.token.claim":"true","access.token.claim":"true","userinfo.token.claim":"true"}},
          {"name":"family name","protocol":"openid-connect","protocolMapper":"oidc-usermodel-attribute-mapper",
           "config":{"user.attribute":"lastName","claim.name":"family_name","jsonType.label":"String",
                     "id.token.claim":"true","access.token.claim":"true","userinfo.token.claim":"true"}}
        ]}'
  fi

  # Assign email + profile as default client scopes for broker-client
  for SCOPE_NAME in email profile; do
    local SCOPE_ID
    SCOPE_ID=$(curl -s "${ORG_KC_URL}/admin/realms/${ORG_REALM}/client-scopes" \
      -H "Authorization: Bearer ${ORG_ADMIN_TOKEN}" \
      | python3 -c "import sys,json; scopes=[s for s in json.load(sys.stdin) if s['name']=='${SCOPE_NAME}']; print(scopes[0]['id'] if scopes else '')")
    if [ -n "${SCOPE_ID}" ]; then
      curl -s -o /dev/null -X PUT \
        "${ORG_KC_URL}/admin/realms/${ORG_REALM}/clients/${CLIENT_UUID}/default-client-scopes/${SCOPE_ID}" \
        -H "Authorization: Bearer ${ORG_ADMIN_TOKEN}"
    fi
  done
  echo "    email/profile scopes assigned to broker-client."
}

# --- Helper: ensure email/profile client scopes on CENTRAL KC -------------
# Same issue as org KCs: realm import only creates scopes in the clientScopes
# array. Without email/profile scopes, JWT tokens for cert-portal won't
# include name/email claims (header shows "Student" instead of the user's name).
ensure_central_client_scopes() {
  echo "==> Ensuring email/profile client scopes on central KC..."

  local EXISTING_SCOPES
  EXISTING_SCOPES=$(curl -s "${CENTRAL_KC_URL}/admin/realms/certchain/client-scopes" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}")

  local HAS_EMAIL HAS_PROFILE
  HAS_EMAIL=$(echo "${EXISTING_SCOPES}" | python3 -c "import sys,json; print(any(s['name']=='email' for s in json.load(sys.stdin)))")
  HAS_PROFILE=$(echo "${EXISTING_SCOPES}" | python3 -c "import sys,json; print(any(s['name']=='profile' for s in json.load(sys.stdin)))")

  if [ "${HAS_EMAIL}" = "False" ]; then
    echo "  Creating 'email' client scope..."
    curl -s -o /dev/null -X POST "${CENTRAL_KC_URL}/admin/realms/certchain/client-scopes" \
      -H "Authorization: Bearer ${ADMIN_TOKEN}" \
      -H "Content-Type: application/json" \
      -d '{
        "name":"email","description":"OpenID Connect built-in scope: email",
        "protocol":"openid-connect",
        "attributes":{"include.in.token.scope":"true","display.on.consent.screen":"true"},
        "protocolMappers":[
          {"name":"email","protocol":"openid-connect","protocolMapper":"oidc-usermodel-attribute-mapper",
           "config":{"user.attribute":"email","claim.name":"email","jsonType.label":"String",
                     "id.token.claim":"true","access.token.claim":"true","userinfo.token.claim":"true"}},
          {"name":"email verified","protocol":"openid-connect","protocolMapper":"oidc-usermodel-attribute-mapper",
           "config":{"user.attribute":"emailVerified","claim.name":"email_verified","jsonType.label":"boolean",
                     "id.token.claim":"true","access.token.claim":"true","userinfo.token.claim":"true"}}
        ]}'
  fi

  if [ "${HAS_PROFILE}" = "False" ]; then
    echo "  Creating 'profile' client scope..."
    curl -s -o /dev/null -X POST "${CENTRAL_KC_URL}/admin/realms/certchain/client-scopes" \
      -H "Authorization: Bearer ${ADMIN_TOKEN}" \
      -H "Content-Type: application/json" \
      -d '{
        "name":"profile","description":"OpenID Connect built-in scope: profile",
        "protocol":"openid-connect",
        "attributes":{"include.in.token.scope":"true","display.on.consent.screen":"true"},
        "protocolMappers":[
          {"name":"username","protocol":"openid-connect","protocolMapper":"oidc-usermodel-attribute-mapper",
           "config":{"user.attribute":"username","claim.name":"preferred_username","jsonType.label":"String",
                     "id.token.claim":"true","access.token.claim":"true","userinfo.token.claim":"true"}},
          {"name":"full name","protocol":"openid-connect","protocolMapper":"oidc-full-name-mapper",
           "config":{"id.token.claim":"true","access.token.claim":"true","userinfo.token.claim":"true"}},
          {"name":"given name","protocol":"openid-connect","protocolMapper":"oidc-usermodel-attribute-mapper",
           "config":{"user.attribute":"firstName","claim.name":"given_name","jsonType.label":"String",
                     "id.token.claim":"true","access.token.claim":"true","userinfo.token.claim":"true"}},
          {"name":"family name","protocol":"openid-connect","protocolMapper":"oidc-usermodel-attribute-mapper",
           "config":{"user.attribute":"lastName","claim.name":"family_name","jsonType.label":"String",
                     "id.token.claim":"true","access.token.claim":"true","userinfo.token.claim":"true"}}
        ]}'
  fi

  # Assign email + profile to cert-portal and verify-api clients
  for CLIENT_NAME in cert-portal verify-api; do
    local CL_UUID
    CL_UUID=$(curl -s "${CENTRAL_KC_URL}/admin/realms/certchain/clients?clientId=${CLIENT_NAME}" \
      -H "Authorization: Bearer ${ADMIN_TOKEN}" | python3 -c "import sys,json; cl=json.load(sys.stdin); print(cl[0]['id'] if cl else '')")
    if [ -z "${CL_UUID}" ]; then continue; fi

    for SCOPE_NAME in email profile; do
      local SCOPE_ID
      SCOPE_ID=$(curl -s "${CENTRAL_KC_URL}/admin/realms/certchain/client-scopes" \
        -H "Authorization: Bearer ${ADMIN_TOKEN}" \
        | python3 -c "import sys,json; scopes=[s for s in json.load(sys.stdin) if s['name']=='${SCOPE_NAME}']; print(scopes[0]['id'] if scopes else '')")
      if [ -n "${SCOPE_ID}" ]; then
        curl -s -o /dev/null -X PUT \
          "${CENTRAL_KC_URL}/admin/realms/certchain/clients/${CL_UUID}/default-client-scopes/${SCOPE_ID}" \
          -H "Authorization: Bearer ${ADMIN_TOKEN}"
      fi
    done
  done
  echo "  email/profile scopes assigned to cert-portal and verify-api."
}

# --- Create OIDC Identity Brokers in central KC ----------------------------
create_idp_broker() {
  local ALIAS=$1
  local DISPLAY=$2
  local ORG_KC_URL=$3
  local ORG_REALM=$4
  local CLIENT_SECRET=$5

  echo "==> Creating IDP broker: ${ALIAS} (${DISPLAY})..."

  local IDP_PAYLOAD
  IDP_PAYLOAD=$(cat <<EOF
{
  "alias": "${ALIAS}",
  "displayName": "${DISPLAY}",
  "providerId": "oidc",
  "enabled": true,
  "trustEmail": true,
  "storeToken": false,
  "addReadTokenRoleOnCreate": false,
  "firstBrokerLoginFlowAlias": "auto-idp-link",
  "hideOnLogin": false,
  "config": {
    "clientId": "broker-client",
    "clientSecret": "${CLIENT_SECRET}",
    "tokenUrl": "${ORG_KC_URL}/realms/${ORG_REALM}/protocol/openid-connect/token",
    "authorizationUrl": "${ORG_KC_URL}/realms/${ORG_REALM}/protocol/openid-connect/auth",
    "logoutUrl": "${ORG_KC_URL}/realms/${ORG_REALM}/protocol/openid-connect/logout",
    "userInfoUrl": "${ORG_KC_URL}/realms/${ORG_REALM}/protocol/openid-connect/userinfo",
    "jwksUrl": "${ORG_KC_URL}/realms/${ORG_REALM}/protocol/openid-connect/certs",
    "issuer": "${ORG_KC_URL}/realms/${ORG_REALM}",
    "validateSignature": "true",
    "useJwksUrl": "true",
    "syncMode": "IMPORT",
    "defaultScope": ""
  }
}
EOF
)

  local HTTP_CODE
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    "${CENTRAL_KC_URL}/admin/realms/certchain/identity-provider/instances" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "${IDP_PAYLOAD}")

  if [ "${HTTP_CODE}" = "201" ]; then
    echo "  Created IDP broker: ${ALIAS}"
  elif [ "${HTTP_CODE}" = "409" ]; then
    echo "  IDP broker ${ALIAS} already exists, updating..."
    curl -s -X PUT \
      "${CENTRAL_KC_URL}/admin/realms/certchain/identity-provider/instances/${ALIAS}" \
      -H "Authorization: Bearer ${ADMIN_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "${IDP_PAYLOAD}"
  else
    echo "  WARNING: Unexpected response ${HTTP_CODE} creating IDP ${ALIAS}"
  fi

  # Add IDP mappers: username prefix, email, org_origin
  echo "  Adding IDP mappers for ${ALIAS}..."
  local PREFIX="${ALIAS:0:2}_"

  # Username prefix mapper
  curl -s -X POST \
    "${CENTRAL_KC_URL}/admin/realms/certchain/identity-provider/instances/${ALIAS}/mappers" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"username-prefix\",
      \"identityProviderAlias\": \"${ALIAS}\",
      \"identityProviderMapper\": \"oidc-username-idp-mapper\",
      \"config\": {
        \"template\": \"${PREFIX}\${ALIAS}.\${CLAIM.preferred_username}\",
        \"syncMode\": \"INHERIT\"
      }
    }" 2>/dev/null || true

  # Hardcoded attribute: org_origin
  curl -s -X POST \
    "${CENTRAL_KC_URL}/admin/realms/certchain/identity-provider/instances/${ALIAS}/mappers" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"org-origin\",
      \"identityProviderAlias\": \"${ALIAS}\",
      \"identityProviderMapper\": \"hardcoded-attribute-idp-mapper\",
      \"config\": {
        \"attribute\": \"org_origin\",
        \"attribute.value\": \"${ALIAS}\",
        \"syncMode\": \"INHERIT\"
      }
    }" 2>/dev/null || true
}

# --- Create Organizations in central KC ------------------------------------
create_organization() {
  local ORG_NAME=$1
  local ORG_DISPLAY=$2
  local EMAIL_DOMAIN=$3
  local IDP_ALIAS=$4

  echo "==> Creating Organization: ${ORG_DISPLAY} (domain: ${EMAIL_DOMAIN})..."

  local ORG_PAYLOAD
  ORG_PAYLOAD=$(cat <<EOF
{
  "name": "${ORG_NAME}",
  "alias": "${ORG_NAME}",
  "enabled": true,
  "description": "${ORG_DISPLAY}",
  "domains": [
    {
      "name": "${EMAIL_DOMAIN}",
      "verified": true
    }
  ],
  "attributes": {}
}
EOF
)

  local HTTP_CODE
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    "${CENTRAL_KC_URL}/admin/realms/certchain/organizations" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "${ORG_PAYLOAD}")

  if [ "${HTTP_CODE}" = "201" ]; then
    echo "  Created Organization: ${ORG_NAME}"
  elif [ "${HTTP_CODE}" = "409" ]; then
    echo "  Organization ${ORG_NAME} already exists, skipping."
  else
    echo "  WARNING: Unexpected response ${HTTP_CODE} creating org ${ORG_NAME}"
  fi

  # Link IDP broker to Organization
  echo "  Linking IDP ${IDP_ALIAS} to Organization ${ORG_NAME}..."
  local ORG_ID
  ORG_ID=$(curl -s "${CENTRAL_KC_URL}/admin/realms/certchain/organizations?search=${ORG_NAME}" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" | python3 -c "import sys,json; orgs=json.load(sys.stdin); print(orgs[0]['id'] if orgs else '')")

  if [ -n "${ORG_ID}" ]; then
    # KC 26+ Organizations API expects a plain JSON string for the IDP alias
    local LINK_HTTP
    LINK_HTTP=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
      "${CENTRAL_KC_URL}/admin/realms/certchain/organizations/${ORG_ID}/identity-providers" \
      -H "Authorization: Bearer ${ADMIN_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "\"${IDP_ALIAS}\"")
    if [ "${LINK_HTTP}" = "204" ] || [ "${LINK_HTTP}" = "409" ]; then
      echo "  Linked IDP ${IDP_ALIAS} to Organization ${ORG_NAME}."
    else
      echo "  WARNING: Unexpected response ${LINK_HTTP} linking IDP to org"
    fi
  else
    echo "  WARNING: Could not find org ID for ${ORG_NAME}"
  fi
}

# --- Enable realm registration for org JIT provisioning -------------------
enable_realm_registration() {
  echo "==> Enabling realm registration for organization JIT provisioning..."
  curl -s -o /dev/null -X PUT \
    "${CENTRAL_KC_URL}/admin/realms/certchain" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{"registrationAllowed": true, "registrationEmailAsUsername": true}'
  echo "  Enabled registrationAllowed + registrationEmailAsUsername."
}

# --- Create custom auto-idp-link flow (skip profile review) ---------------
create_auto_idp_link_flow() {
  echo "==> Creating auto-idp-link authentication flow..."

  local HTTP_CODE
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    "${CENTRAL_KC_URL}/admin/realms/certchain/authentication/flows/first%20broker%20login/copy" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{"newName": "auto-idp-link"}')

  if [ "${HTTP_CODE}" = "201" ]; then
    echo "  Created auto-idp-link flow."
  elif [ "${HTTP_CODE}" = "409" ]; then
    echo "  auto-idp-link flow already exists."
    return
  else
    echo "  WARNING: Unexpected response ${HTTP_CODE} creating flow"
    return
  fi

  # Disable "Review Profile" and "Confirm link existing account" steps
  # — we trust org IDP data and want seamless JIT provisioning
  local EXECS
  EXECS=$(curl -s "${CENTRAL_KC_URL}/admin/realms/certchain/authentication/flows/auto-idp-link/executions" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}")

  echo "${EXECS}" | python3 -c "
import sys, json, urllib.request, urllib.error, ssl
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

execs = json.load(sys.stdin)
kc = '${CENTRAL_KC_URL}'
token = '${ADMIN_TOKEN}'
headers = {'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'}

disable_providers = {'idp-review-profile': 'Review Profile', 'idp-confirm-link': 'Confirm link existing account'}
for e in execs:
    pid = e.get('providerId', '')
    if pid in disable_providers:
        payload = json.dumps({'id': e['id'], 'requirement': 'DISABLED', 'displayName': e.get('displayName',''), 'providerId': pid}).encode()
        req = urllib.request.Request(f'{kc}/admin/realms/certchain/authentication/flows/auto-idp-link/executions',
            data=payload, headers=headers, method='PUT')
        urllib.request.urlopen(req, context=ctx)
        print(f'  Disabled {disable_providers[pid]} step.')
"
}

# --- Disable Organization flow -----------------------------------------------
# KC 26's Organization Identity-First Login intercepts the browser flow and
# blocks first-time users with "no account yet" before IDP buttons are shown.
# We disable the Organization flow; students click Login → see IDP buttons on
# central KC login page → click their org → authenticate on org KC → JIT
# provisioned in central KC via auto-idp-link flow.
# Organizations + IDPs are still created above for admin visibility.
disable_organization_flow() {
  echo "==> Disabling Organization flow in browser authentication..."

  local BROWSER_EXECS
  BROWSER_EXECS=$(curl -s "${CENTRAL_KC_URL}/admin/realms/certchain/authentication/flows/browser/executions" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}")

  local ORG_EXEC_ID
  ORG_EXEC_ID=$(echo "${BROWSER_EXECS}" | python3 -c "
import sys, json
for e in json.load(sys.stdin):
    if e.get('displayName') == 'Organization' and e.get('level', 99) == 0:
        print(e['id'])
        break
" 2>/dev/null)

  if [ -n "${ORG_EXEC_ID}" ]; then
    local HTTP_CODE
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X PUT \
      "${CENTRAL_KC_URL}/admin/realms/certchain/authentication/flows/browser/executions" \
      -H "Authorization: Bearer ${ADMIN_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "{\"id\": \"${ORG_EXEC_ID}\", \"requirement\": \"DISABLED\"}")
    echo "  Organization flow: DISABLED (HTTP ${HTTP_CODE})"
  else
    echo "  Organization flow not found in browser flow (may already be disabled)"
  fi
}

# --- Execute ---------------------------------------------------------------

# Enable realm registration (required for org JIT provisioning in KC 26+)
enable_realm_registration

# Create auto-idp-link flow (before creating IDPs that reference it)
create_auto_idp_link_flow

# Ensure email/profile scopes on central KC (for cert-portal JWT name claims)
ensure_central_client_scopes

# Update broker-client redirect URIs + ensure OIDC scopes on each org KC
update_org_broker_redirect "${TP_KC_URL}" "techpulse" "broker-secret-techpulse"
ensure_org_client_scopes "${TP_KC_URL}" "techpulse"
update_org_broker_redirect "${DF_KC_URL}" "dataforge" "broker-secret-dataforge"
ensure_org_client_scopes "${DF_KC_URL}" "dataforge"
update_org_broker_redirect "${NP_KC_URL}" "neuralpath" "broker-secret-neuralpath"
ensure_org_client_scopes "${NP_KC_URL}" "neuralpath"

# Create IDP brokers in central KC
create_idp_broker "techpulse" "TechPulse Academy" "${TP_KC_URL}" "techpulse" "broker-secret-techpulse"
create_idp_broker "dataforge" "DataForge Institute" "${DF_KC_URL}" "dataforge" "broker-secret-dataforge"
create_idp_broker "neuralpath" "NeuralPath Labs" "${NP_KC_URL}" "neuralpath" "broker-secret-neuralpath"

# Create Organizations with email-domain-based IDP routing
create_organization "techpulse" "TechPulse Academy" "techpulse.demo" "techpulse"
create_organization "dataforge" "DataForge Institute" "dataforge.demo" "dataforge"
create_organization "neuralpath" "NeuralPath Labs" "neuralpath.demo" "neuralpath"

# Disable Organization browser flow (app-level kc_idp_hint handles routing)
disable_organization_flow

echo ""
echo "==> Keycloak configuration complete!"
echo "    - Realm registration enabled for JIT provisioning"
echo "    - auto-idp-link flow: no profile review, no link confirmation"
echo "    - 3 OIDC Identity Brokers visible on central KC login page"
echo "    - 3 Organizations with email-domain routing configured"
echo "    - Organization browser flow: DISABLED (IDP buttons used instead)"
echo "    - email/profile client scopes ensured on all KCs (org + central)"
