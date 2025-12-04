#!/bin/bash
set -e

# Configuration
ARTIFACTORY_REPO="demo-dev-npm-remote-cache"
PACKAGES_TO_DELETE=("ejs" "lodash")
WAIVER_POLICY_PATTERN="jfrog-waiver-policy-"

echo "Starting cleanup..."

# 1. Local Cleanup
echo "Cleaning local npm cache..."
npm cache clean --force
rm -rf node_modules package-lock.json
echo "Local cleanup done."

# 2. Artifactory Cache Deletion
echo "Deleting packages from Artifactory cache..."
for pkg in "${PACKAGES_TO_DELETE[@]}"; do
    echo "Deleting $pkg..."
    if ! jf rt del "$ARTIFACTORY_REPO/$pkg" --quiet 2>/dev/null; then
        echo "Package $pkg not found or already deleted."
    fi
done
echo "Artifactory cleanup done."

# 3. Catalog Waiver Removal
echo "Removing waiver policies from Catalog..."

# Get Platform URL and User from jf config
PLATFORM_URL=$(jf c show | grep "JFrog Platform URL" | awk '{print $4}')
USER=$(jf c show | grep "User" | head -n 1 | awk '{print $2}')

if [ -z "$PLATFORM_URL" ]; then
    echo "Error: Could not find JFrog Platform URL in jf config."
    exit 1
fi

if [ -z "$USER" ]; then
    echo "Error: Could not find User in jf config."
    exit 1
fi

echo "Platform URL: $PLATFORM_URL"
echo "User: $USER"

# Create Access Token
echo "Creating access token (expires in 60s)..."
# Create token with 60 seconds expiry
TOKEN_RESPONSE=$(jf atc "$USER" --expiry 60)
ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')
TOKEN_ID=$(echo "$TOKEN_RESPONSE" | jq -r '.token_id')

if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" == "null" ]; then
    echo "Error: Failed to create access token."
    exit 1
fi

# Function to revoke token
revoke_token() {
    if [ -n "$TOKEN_ID" ]; then
        echo "Revoking access token..."
      
        
        REVOKE_URL="${PLATFORM_URL}access/api/v1/tokens/$TOKEN_ID"
        curl -s -X DELETE "$REVOKE_URL" \
            -H "Authorization: Bearer $ACCESS_TOKEN" > /dev/null
        echo "Token revoked."
    fi
}

# Set trap to revoke token on exit
trap revoke_token EXIT

CATALOG_API_URL="${PLATFORM_URL}catalog/api/v1/custom/graphql"

# Search for policies
echo "Searching for waiver policies matching '$WAIVER_POLICY_PATTERN'..."
SEARCH_QUERY="{\"query\": \"{ customCatalogLabel { searchLabels(where: {nameContainsFold: \\\"$WAIVER_POLICY_PATTERN\\\"}, first: 100) { edges { node { name } } } } }\"}"

SEARCH_RESPONSE=$(curl -s -X POST "$CATALOG_API_URL" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$SEARCH_QUERY")

# Parse response to get names
# Check if jq is available
if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed. Please install jq to run this script."
    exit 1
fi

LABELS_TO_DELETE=$(echo "$SEARCH_RESPONSE" | jq -r '.data.customCatalogLabel.searchLabels.edges[].node.name // empty')

if [ -z "$LABELS_TO_DELETE" ]; then
    echo "No matching waiver policies found."
else
    echo "Found policies to delete:"
    echo "$LABELS_TO_DELETE"

    # Delete each label
    echo "$LABELS_TO_DELETE" | while read -r label; do
        if [ -n "$label" ]; then
            echo "Deleting label: $label"
            DELETE_MUTATION="{\"query\": \"mutation { customCatalogLabel { deleteCustomCatalogLabel(label:{name:\\\"$label\\\"}) } }\"}"
            
            DELETE_RESPONSE=$(curl -s -X POST "$CATALOG_API_URL" \
                -H "Authorization: Bearer $ACCESS_TOKEN" \
                -H "Content-Type: application/json" \
                -d "$DELETE_MUTATION")
                
            echo "Response: $DELETE_RESPONSE"
        fi
    done
fi

echo "Cleanup completed successfully!"
