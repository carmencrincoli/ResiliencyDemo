#!/bin/bash
# Step 1: Setup Storage Account and Upload Scripts
# This script creates a storage account, uploads deployment scripts, and updates the bicep parameters file

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'
NC='\033[0m' # No Color

# Default values
STORAGE_ACCOUNT_PREFIX="ecommscripts"
PARAMETERS_FILE="main.bicepparam"
UPLOAD_ASSETS_PATH="./assets"

# Function to display usage
usage() {
    echo "Usage: $0 -g RESOURCE_GROUP -l LOCATION [-s STORAGE_PREFIX] [-p PARAMETERS_FILE] [-u UPLOAD_PATH]"
    echo ""
    echo "Required arguments:"
    echo "  -g RESOURCE_GROUP        Name of the Azure resource group"
    echo "  -l LOCATION              Azure region location"
    echo ""
    echo "Optional arguments:"
    echo "  -s STORAGE_PREFIX        Storage account prefix (default: ecommscripts)"
    echo "  -p PARAMETERS_FILE       Path to bicepparam file (default: main.bicepparam)"
    echo "  -u UPLOAD_PATH           Path to assets directory (default: ./assets)"
    echo "  -h                       Display this help message"
    echo ""
    exit 1
}

# Parse command line arguments
while getopts "g:l:s:p:u:h" opt; do
    case $opt in
        g) RESOURCE_GROUP_NAME="$OPTARG" ;;
        l) LOCATION="$OPTARG" ;;
        s) STORAGE_ACCOUNT_PREFIX="$OPTARG" ;;
        p) PARAMETERS_FILE="$OPTARG" ;;
        u) UPLOAD_ASSETS_PATH="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

# Check required arguments
if [ -z "$RESOURCE_GROUP_NAME" ] || [ -z "$LOCATION" ]; then
    echo -e "${RED}❌ Error: Resource group and location are required${NC}"
    usage
fi

# Set container name to the folder name from UploadAssetsPath
CONTAINER_NAME=$(basename "$UPLOAD_ASSETS_PATH")

echo -e "${GREEN}🚀 Starting Step 1: Storage Account Setup and Script Upload${NC}"
echo -e "${CYAN}📍 Resource Group: $RESOURCE_GROUP_NAME${NC}"
echo -e "${CYAN}🌍 Location: $LOCATION${NC}"
echo ""

# Read storage account name from bicepparam file
echo -e "${YELLOW}📖 Reading storage account name from $PARAMETERS_FILE...${NC}"

if [ ! -f "$PARAMETERS_FILE" ]; then
    echo -e "${RED}❌ Parameters file not found: $PARAMETERS_FILE${NC}"
    exit 1
fi

STORAGE_ACCOUNT_NAME=""

# Extract storage account name from the parameter file
if grep -q "param scriptStorageAccount = '" "$PARAMETERS_FILE"; then
    STORAGE_ACCOUNT_NAME=$(grep "param scriptStorageAccount = '" "$PARAMETERS_FILE" | sed -n "s/.*param scriptStorageAccount = '\([^']*\)'.*/\1/p" | xargs)
    if [ -z "$STORAGE_ACCOUNT_NAME" ]; then
        echo -e "${CYAN}  ℹ️  Storage account name is blank in parameters file${NC}"
        STORAGE_ACCOUNT_NAME=""
    else
        echo -e "${GREEN}  ✅ Found storage account name in parameters file: $STORAGE_ACCOUNT_NAME${NC}"
    fi
else
    echo -e "${CYAN}  ℹ️  scriptStorageAccount parameter not found in parameters file${NC}"
fi

# Determine if we need to create a new storage account or use existing
CREATE_NEW_ACCOUNT=false
STORAGE_ACCOUNT_EXISTS=false

if [ -z "$STORAGE_ACCOUNT_NAME" ]; then
    # Generate a new unique storage account name
    RANDOM_SUFFIX=$((1000 + RANDOM % 9000))
    STORAGE_ACCOUNT_NAME="${STORAGE_ACCOUNT_PREFIX}${RANDOM_SUFFIX}"
    STORAGE_ACCOUNT_NAME=$(echo "$STORAGE_ACCOUNT_NAME" | tr '[:upper:]' '[:lower:]')
    echo -e "${CYAN}  🎲 Generated new storage account name: $STORAGE_ACCOUNT_NAME${NC}"
    CREATE_NEW_ACCOUNT=true
else
    # Check if storage account exists in the resource group
    echo -e "${YELLOW}  🔍 Checking if storage account exists in resource group...${NC}"
    
    if az storage account show --name "$STORAGE_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP_NAME" &>/dev/null; then
        echo -e "${GREEN}  ✅ Storage account '$STORAGE_ACCOUNT_NAME' exists in resource group${NC}"
        STORAGE_ACCOUNT_EXISTS=true
    else
        echo -e "${CYAN}  ℹ️  Storage account does not exist in resource group${NC}"
        
        # Check if the name is globally available
        echo -e "${YELLOW}  🌐 Checking if storage account name is globally available...${NC}"
        NAME_CHECK_RESULT=$(az storage account check-name --name "$STORAGE_ACCOUNT_NAME" 2>/dev/null)
        NAME_AVAILABLE=$(echo "$NAME_CHECK_RESULT" | grep -o '"nameAvailable"[[:space:]]*:[[:space:]]*[^,}]*' | sed 's/.*:[[:space:]]*//' | tr -d ' ')
        
        if [ "$NAME_AVAILABLE" = "true" ]; then
            echo -e "${GREEN}  ✅ Storage account name is globally available${NC}"
            CREATE_NEW_ACCOUNT=true
        elif [ "$NAME_AVAILABLE" = "false" ]; then
            # Get the reason why it's not available
            REASON=$(echo "$NAME_CHECK_RESULT" | grep -o '"reason"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*:[[:space:]]*"//' | tr -d '"')
            MESSAGE=$(echo "$NAME_CHECK_RESULT" | grep -o '"message"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*:[[:space:]]*"//' | tr -d '"')
            
            echo ""
            echo -e "${RED}❌ ERROR: Storage account name '$STORAGE_ACCOUNT_NAME' is not available${NC}"
            echo -e "${RED}  Reason: $REASON${NC}"
            echo -e "${RED}  Message: $MESSAGE${NC}"
            echo ""
            echo -e "${YELLOW}💡 Please update the 'scriptStorageAccount' parameter in $PARAMETERS_FILE with either:${NC}"
            echo -e "${YELLOW}   • An empty string ('') to auto-generate a new name${NC}"
            echo -e "${YELLOW}   • A different globally unique storage account name${NC}"
            echo ""
            exit 1
        else
            # Unable to determine availability - possibly an API error
            echo -e "${RED}❌ ERROR: Unable to check storage account name availability${NC}"
            echo -e "${RED}  Received: '$NAME_AVAILABLE'${NC}"
            echo -e "${RED}  Full response: $NAME_CHECK_RESULT${NC}"
            echo ""
            exit 1
        fi
    fi
fi

echo -e "${CYAN}💾 Storage Account: $STORAGE_ACCOUNT_NAME${NC}"
echo ""

# Check if tar command is available for compression
echo -e "${YELLOW}🔍 Checking system requirements...${NC}"
if command -v tar &>/dev/null; then
    echo -e "${GREEN}✅ tar command available for archive compression${NC}"
else
    echo -e "${YELLOW}⚠️  tar command not found - archives compression may fail${NC}"
    echo -e "${YELLOW}💡 Please install tar using your package manager (e.g., apt-get install tar)${NC}"
fi

# Check if resource group exists, create if it doesn't
echo -e "${YELLOW}🔍 Checking if resource group exists...${NC}"
RG_EXISTS=$(az group exists --name "$RESOURCE_GROUP_NAME" 2>/dev/null | tr -d '[:space:]')
if [ "$RG_EXISTS" != "true" ]; then
    echo -e "${YELLOW}📁 Creating resource group: $RESOURCE_GROUP_NAME${NC}"
    az group create --name "$RESOURCE_GROUP_NAME" --location "$LOCATION"
    echo -e "${GREEN}✅ Resource group created successfully${NC}"
else
    echo -e "${GREEN}✅ Resource group already exists${NC}"
fi

# Create or use existing storage account
if [ "$CREATE_NEW_ACCOUNT" = true ]; then
    # Create storage account with anonymous access
    echo -e "${YELLOW}💾 Creating storage account with anonymous access...${NC}"
    az storage account create \
        --name "$STORAGE_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --access-tier Hot \
        --allow-blob-public-access true \
        --min-tls-version TLS1_2 \
        --https-only true

    echo -e "${GREEN}✅ Storage account created successfully${NC}"

    # Ensure blob public access is enabled (sometimes needs explicit update)
    echo -e "${YELLOW}🔧 Ensuring blob public access is enabled...${NC}"
    if ! az storage account update \
        --name "$STORAGE_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --allow-blob-public-access true &>/dev/null; then
        echo -e "${YELLOW}⚠️  Warning: Failed to update blob public access setting${NC}"
    fi

    # Wait for storage account to be fully ready
    echo -e "${YELLOW}⏳ Waiting for storage account to be fully provisioned...${NC}"
    sleep 10
else
    echo -e "${GREEN}♻️  Using existing storage account: $STORAGE_ACCOUNT_NAME${NC}"
    
    # Verify blob public access is enabled on existing account
    echo -e "${YELLOW}🔧 Verifying blob public access is enabled...${NC}"
    if ! az storage account update \
        --name "$STORAGE_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --allow-blob-public-access true &>/dev/null; then
        echo -e "${YELLOW}⚠️  Warning: Failed to update blob public access setting${NC}"
    fi
fi

# Get storage account key
echo -e "${YELLOW}🔑 Retrieving storage account key...${NC}"
STORAGE_KEY=$(az storage account keys list --account-name "$STORAGE_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query '[0].value' -o tsv)

if [ -z "$STORAGE_KEY" ]; then
    echo -e "${RED}❌ Failed to get storage account key${NC}"
    exit 1
fi

# Create or verify container with public blob access for direct URI access
echo -e "${YELLOW}📦 Creating/verifying container with public blob access...${NC}"

# Check if container exists
CONTAINER_EXISTS=$(az storage container exists \
    --name "$CONTAINER_NAME" \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --account-key "$STORAGE_KEY" \
    --query "exists" -o tsv 2>/dev/null)

if [ "$CONTAINER_EXISTS" = "true" ]; then
    echo -e "${GREEN}  ✅ Container already exists${NC}"
else
    az storage container create \
        --name "$CONTAINER_NAME" \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --account-key "$STORAGE_KEY" \
        --public-access blob

    echo -e "${GREEN}  ✅ Container created successfully${NC}"
fi

# Verify and ensure container public access is set correctly
echo -e "${YELLOW}🔧 Verifying container public access...${NC}"
az storage container set-permission \
    --name "$CONTAINER_NAME" \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --account-key "$STORAGE_KEY" \
    --public-access blob &>/dev/null || echo -e "${YELLOW}⚠️  Warning: Failed to set container permissions${NC}"

# Upload all assets from upload directory with special handling for archives
echo -e "${YELLOW}📤 Uploading deployment assets...${NC}"

if [ ! -d "$UPLOAD_ASSETS_PATH" ]; then
    echo -e "${RED}❌ Upload assets directory not found: $UPLOAD_ASSETS_PATH${NC}"
    echo -e "${YELLOW}💡 Please ensure the assets directory exists and contains your deployment files${NC}"
    exit 1
fi

# Create a temporary directory for processing
TEMP_DIR=$(mktemp -d -t predeploy-temp-XXXXXX)
echo -e "${GRAY}📁 Created temporary directory: $TEMP_DIR${NC}"

# Cleanup function
cleanup() {
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
        echo -e "${GRAY}🧹 Cleaned up temporary directory${NC}"
    fi
}
trap cleanup EXIT

# Check for archives directory and compress subfolders
ARCHIVES_PATH="$UPLOAD_ASSETS_PATH/archives"
if [ -d "$ARCHIVES_PATH" ]; then
    echo -e "${YELLOW}🗜️  Processing archives directory...${NC}"
    
    ARCHIVE_COUNT=$(find "$ARCHIVES_PATH" -mindepth 1 -maxdepth 1 -type d | wc -l)
    if [ "$ARCHIVE_COUNT" -gt 0 ]; then
        echo -e "${CYAN}📦 Found $ARCHIVE_COUNT subfolders to compress:${NC}"
        
        for SUBFOLDER in "$ARCHIVES_PATH"/*; do
            if [ -d "$SUBFOLDER" ]; then
                SUBFOLDER_NAME=$(basename "$SUBFOLDER")
                ARCHIVE_NAME="${SUBFOLDER_NAME}.tar.gz"
                ARCHIVE_DEST_PATH="$TEMP_DIR/$ARCHIVE_NAME"
                
                echo -e "${GRAY}  🗜️  Compressing $SUBFOLDER_NAME -> $ARCHIVE_NAME${NC}"
                
                # Use tar command to create compressed archive
                if tar -czf "$ARCHIVE_DEST_PATH" -C "$SUBFOLDER" .; then
                    echo -e "${GREEN}    ✅ Created: $ARCHIVE_NAME${NC}"
                else
                    echo -e "${YELLOW}⚠️  Failed to compress $SUBFOLDER_NAME${NC}"
                fi
            fi
        done
    fi
fi

# Copy all other files and directories EXCEPT the archives directory
echo -e "${YELLOW}📋 Copying other files (excluding archives directory)...${NC}"

# Get all files from assets directory except anything under the archives subdirectory
echo -e "${GRAY}  📁 Excluding archives directory and its contents from individual file upload${NC}"

OTHER_FILES_COUNT=0
# Temporarily disable exit on error for the file copy loop
set +e

# Get the absolute path for proper prefix stripping
UPLOAD_ASSETS_ABSOLUTE=$(cd "$UPLOAD_ASSETS_PATH" && pwd)

while IFS= read -r -d '' FILE; do
    # Strip the assets path prefix to get relative path
    RELATIVE_PATH="${FILE#$UPLOAD_ASSETS_ABSOLUTE/}"
    
    # Skip if file is under archives directory
    if [[ "$RELATIVE_PATH" == archives/* ]]; then
        continue
    fi
    
    DEST_PATH="$TEMP_DIR/$RELATIVE_PATH"
    DEST_DIR=$(dirname "$DEST_PATH")
    
    mkdir -p "$DEST_DIR"
    if cp "$FILE" "$DEST_PATH"; then
        echo -e "${GRAY}  📄 $RELATIVE_PATH${NC}"
        ((OTHER_FILES_COUNT++))
    else
        echo -e "${YELLOW}  ⚠️  Failed to copy: $RELATIVE_PATH (Error: $?)${NC}"
    fi
done < <(find "$UPLOAD_ASSETS_ABSOLUTE" -type f -print0)

# Re-enable exit on error
set -e

echo -e "${CYAN}  📋 Found $OTHER_FILES_COUNT non-archive files to upload${NC}"
echo ""

# Get all files in temp directory to show what will be uploaded
ASSET_FILES_COUNT=$(find "$TEMP_DIR" -type f 2>/dev/null | wc -l)
if [ "$ASSET_FILES_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}⚠️  No files found to upload${NC}"
    exit 1
fi

echo -e "${CYAN}📋 Final upload list ($ASSET_FILES_COUNT files):${NC}"
while IFS= read -r FILE; do
    RELATIVE_PATH="${FILE#$TEMP_DIR/}"
    echo -e "${GRAY}  • $RELATIVE_PATH${NC}"
done < <(find "$TEMP_DIR" -type f)
echo ""

# Use batch upload for much faster performance (uploads in parallel)
echo -e "${CYAN}⚡ Batch uploading all processed assets...${NC}"
echo -e "${GRAY}  Source directory: $TEMP_DIR${NC}"

# Verify temp directory exists and has files
if [ ! -d "$TEMP_DIR" ]; then
    echo -e "${RED}❌ Temporary directory does not exist: $TEMP_DIR${NC}"
    exit 1
fi

# Change to temp directory and upload from there
cd "$TEMP_DIR" || exit 1

if az storage blob upload-batch \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --account-key "$STORAGE_KEY" \
    --destination "$CONTAINER_NAME" \
    --source . \
    --overwrite \
    --pattern "*" \
    --content-type "application/octet-stream" \
    --output none 2>&1 | grep -v "^Alive"; then
    echo -e "${GREEN}✅ All assets uploaded successfully via batch upload${NC}"
else
    echo -e "${RED}❌ Failed to batch upload assets${NC}"
    echo -e "${YELLOW}💡 Check the error messages above for details${NC}"
    exit 1
fi

# Return to original directory
cd - >/dev/null

# Get list of uploaded assets for verification
echo -e "${YELLOW}🔍 Verifying uploaded scripts...${NC}"
echo ""
az storage blob list --account-name "$STORAGE_ACCOUNT_NAME" --account-key "$STORAGE_KEY" --container-name "$CONTAINER_NAME" --output table
echo ""

# Get uploaded assets list
mapfile -t UPLOADED_ASSETS < <(az storage blob list --account-name "$STORAGE_ACCOUNT_NAME" --account-key "$STORAGE_KEY" --container-name "$CONTAINER_NAME" --query "[].name" -o tsv)

# Get storage endpoint for URLs
STORAGE_ENDPOINT=$(az storage account show --name "$STORAGE_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query primaryEndpoints.blob -o tsv)

# Display asset URLs
echo -e "${GREEN}🌐 Asset URLs (publicly accessible):${NC}"
for ASSET in "${UPLOADED_ASSETS[@]}"; do
    URL="${STORAGE_ENDPOINT}${CONTAINER_NAME}/$ASSET"
    echo -e "${CYAN}  📄 $ASSET: $URL${NC}"
done
echo ""

# Update main.bicepparam file
echo -e "${YELLOW}📝 Updating parameters file: $PARAMETERS_FILE${NC}"

if [ ! -f "$PARAMETERS_FILE" ]; then
    echo -e "${RED}❌ Parameters file not found: $PARAMETERS_FILE${NC}"
    exit 1
fi

# Read current parameters file
PARAM_CONTENT=$(cat "$PARAMETERS_FILE")
PARAMETER_UPDATED=false

# Check if scriptStorageAccount parameter already exists
if grep -q "param scriptStorageAccount = '" "$PARAMETERS_FILE"; then
    CURRENT_VALUE=$(grep "param scriptStorageAccount = '" "$PARAMETERS_FILE" | sed -n "s/.*param scriptStorageAccount = '\([^']*\)'.*/\1/p")
    if [ "$CURRENT_VALUE" != "$STORAGE_ACCOUNT_NAME" ]; then
        # Update existing parameter
        sed -i.bak "s/param scriptStorageAccount = '.*'/param scriptStorageAccount = '$STORAGE_ACCOUNT_NAME'/" "$PARAMETERS_FILE"
        echo -e "${CYAN}  ✏️  Updated scriptStorageAccount parameter: '$CURRENT_VALUE' -> '$STORAGE_ACCOUNT_NAME'${NC}"
        PARAMETER_UPDATED=true
    else
        echo -e "${GREEN}  ✅ scriptStorageAccount parameter already contains correct value: '$STORAGE_ACCOUNT_NAME'${NC}"
    fi
else
    # Add new parameter after the existing Azure Stack HCI configuration
    if grep -q "param vmImageName" "$PARAMETERS_FILE"; then
        # Insert before vmImageName line
        sed -i.bak "/param vmImageName/i param scriptStorageAccount = '$STORAGE_ACCOUNT_NAME'" "$PARAMETERS_FILE"
        echo -e "${CYAN}  ➕ Added new scriptStorageAccount parameter with value: '$STORAGE_ACCOUNT_NAME'${NC}"
        PARAMETER_UPDATED=true
    else
        # Fallback: append at the end
        echo "param scriptStorageAccount = '$STORAGE_ACCOUNT_NAME'" >> "$PARAMETERS_FILE"
        echo -e "${CYAN}  ➕ Added new scriptStorageAccount parameter with value: '$STORAGE_ACCOUNT_NAME' (at end)${NC}"
        PARAMETER_UPDATED=true
    fi
fi

# Remove backup file if created
rm -f "${PARAMETERS_FILE}.bak"

if [ "$PARAMETER_UPDATED" = true ]; then
    echo -e "${GREEN}✅ Parameters file updated successfully${NC}"
else
    echo -e "${GREEN}✅ Parameters file already up to date${NC}"
fi
echo ""

# Summary
echo -e "${GREEN}🎉 Step 1 Complete! Storage Account Setup and Asset Upload Successful${NC}"
echo ""
echo -e "${WHITE}📋 Summary:${NC}"
echo -e "${CYAN}  💾 Storage Account: $STORAGE_ACCOUNT_NAME${NC}"
echo -e "${CYAN}  📦 Container: $CONTAINER_NAME${NC}"
echo -e "${CYAN}  📄 Assets Uploaded: ${#UPLOADED_ASSETS[@]}${NC}"
echo -e "${CYAN}  🗜️  Compressed archives: Created .tar.gz files from \\assets\\archives subfolders${NC}"
echo -e "${CYAN}  📋 Other assets: Uploaded all files from \\assets EXCEPT the \\archives directory${NC}"
echo -e "${YELLOW}  🚫 Excluded: \\assets\\archives directory (only compressed versions uploaded)${NC}"
echo -e "${GREEN}  ✅ All assets processed and uploaded successfully!${NC}"
echo -e "${CYAN}  📝 Parameters File Updated: $PARAMETERS_FILE${NC}"
echo ""
echo -e "${YELLOW}🚀 Next Step: Run your Bicep deployment${NC}"
echo -e "${GRAY}   az deployment group create --resource-group \"$RESOURCE_GROUP_NAME\" --template-file \"infra/main.bicep\" --parameters \"$PARAMETERS_FILE\"${NC}"
echo ""
