#!/bin/bash
set -e

# --- Configuration ---
PLATFORM_URL="https://winnik.jfrog.io/" 
USER="yanirw@jfrog.com"
ARTIFACTORY_REPO="demo-dev-npm-remote-cache"
PACKAGES_TO_DELETE=("ejs" "lodash")
# ---------------------

clear
echo "===================================================="
echo "🚀 JFrog Curation: Global Environment Reset"
echo "===================================================="

# 1. Local Cleanup
echo "➜ Cleaning local npm environment..."
npm cache clean --force > /dev/null 2>&1
rm -rf node_modules package-lock.json
echo "✔ Local cleanup done."

# 2. Artifactory Cache Deletion
echo "➜ Clearing Artifactory cache..."
for pkg in "${PACKAGES_TO_DELETE[@]}"; do
    jf rt del "$ARTIFACTORY_REPO/$pkg" --server-id "Default-Server" --quiet > /dev/null 2>&1
done
echo "✔ Artifactory cache is clear."

# 3. Catalog Waiver Removal
echo "➜ Scanning for active waiver labels..."

# Create temporary Access Token
TOKEN_RESPONSE=$(jf atc "$USER" --server-id "Default-Server" --expiry 60)
ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')
TOKEN_ID=$(echo "$TOKEN_RESPONSE" | jq -r '.token_id')

# Cleanup token on script exit
revoke_token() {
    if [ -n "$TOKEN_ID" ]; then
        curl -s -X DELETE "${PLATFORM_URL%/}/access/api/v1/tokens/$TOKEN_ID" \
            -H "Authorization: Bearer $ACCESS_TOKEN" > /dev/null
    fi
}
trap revoke_token EXIT

CATALOG_API_URL="${PLATFORM_URL%/}/catalog/api/v1/custom/graphql"

# DYNAMIC SEARCH: Looking for anything containing "jfrog-waiver-policy-"
SEARCH_QUERY="{\"query\": \"{ customCatalogLabel { searchLabels(where: {nameContainsFold: \\\"jfrog-waiver-policy-\\\"}, first: 100) { edges { node { name } } } } }\"}"

SEARCH_RESPONSE=$(curl -s -X POST "$CATALOG_API_URL" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$SEARCH_QUERY")

# Extract all matching labels
LABELS=$(echo "$SEARCH_RESPONSE" | jq -r '.data.customCatalogLabel.searchLabels.edges[].node.name // empty')

if [ -z "$LABELS" ]; then
    echo "✔ No active waiver labels found."
else
    for label in $LABELS; do
        echo "➜ Deleting label: $label"
        DELETE_MUTATION="{\"query\": \"mutation { customCatalogLabel { deleteCustomCatalogLabel(label:{name:\\\"$label\\\"}) } }\"}"
        curl -s -X POST "$CATALOG_API_URL" \
            -H "Authorization: Bearer $ACCESS_TOKEN" \
            -H "Content-Type: application/json" \
            -d "$DELETE_MUTATION" > /dev/null
    done
    echo "✔ All previous waivers purged."
fi

echo "===================================================="
echo "✅ SUCCESS: Ready for Curation demo."
echo "===================================================="