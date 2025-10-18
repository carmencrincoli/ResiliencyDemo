# Step 1: Setup Storage Account and Upload Scripts
# This script creates a storage account, uploads deployment scripts, and updates the bicep parameters file

param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$Location,
    
    [Parameter(Mandatory=$false)]
    [string]$StorageAccountPrefix = "ecommscripts",
    
    [Parameter(Mandatory=$false)]
    [string]$ParametersFile = "main.bicepparam",
    
    [Parameter(Mandatory=$false)]
    [string]$UploadAssetsPath = ".\assets"
)

# Set container name to the folder name from UploadAssetsPath
$ContainerName = Split-Path -Leaf $UploadAssetsPath

Write-Host "🚀 Starting Step 1: Storage Account Setup and Script Upload" -ForegroundColor Green
Write-Host "📍 Resource Group: $ResourceGroupName" -ForegroundColor Cyan
Write-Host "🌍 Location: $Location" -ForegroundColor Cyan
Write-Host ""

# Read storage account name from bicepparam file
Write-Host "📖 Reading storage account name from $ParametersFile..." -ForegroundColor Yellow

if (-not (Test-Path $ParametersFile)) {
    Write-Error "❌ Parameters file not found: $ParametersFile"
    exit 1
}

$paramContent = Get-Content $ParametersFile -Raw
$storageAccountName = $null

# Extract storage account name from the parameter file
if ($paramContent -match "param scriptStorageAccount = '([^']*)'") {
    $storageAccountName = $Matches[1].Trim()
    if ([string]::IsNullOrWhiteSpace($storageAccountName)) {
        Write-Host "  ℹ️  Storage account name is blank in parameters file" -ForegroundColor Cyan
        $storageAccountName = $null
    } else {
        Write-Host "  ✅ Found storage account name in parameters file: $storageAccountName" -ForegroundColor Green
    }
} else {
    Write-Host "  ℹ️  scriptStorageAccount parameter not found in parameters file" -ForegroundColor Cyan
}

# Determine if we need to create a new storage account or use existing
$createNewAccount = $false

if ($null -eq $storageAccountName) {
    # Generate a new unique storage account name
    $randomSuffix = Get-Random -Minimum 1000 -Maximum 9999
    $storageAccountName = "$StorageAccountPrefix$randomSuffix".ToLower()
    Write-Host "  🎲 Generated new storage account name: $storageAccountName" -ForegroundColor Cyan
    $createNewAccount = $true
} else {
    # Check if storage account exists in the resource group
    Write-Host "  🔍 Checking if storage account exists in resource group..." -ForegroundColor Yellow

    az storage account show --name $storageAccountName --resource-group $ResourceGroupName 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✅ Storage account '$storageAccountName' exists in resource group" -ForegroundColor Green
    } else {
        Write-Host "  ℹ️  Storage account does not exist in resource group" -ForegroundColor Cyan
        
        # Check if the name is globally available
        Write-Host "  🌐 Checking if storage account name is globally available..." -ForegroundColor Yellow
        $nameAvailability = az storage account check-name --name $storageAccountName --query "nameAvailable" -o tsv 2>$null
        
        if ($nameAvailability -eq "true") {
            Write-Host "  ✅ Storage account name is globally available" -ForegroundColor Green
            $createNewAccount = $true
        } else {
            # Get the reason why it's not available
            $reason = az storage account check-name --name $storageAccountName --query "reason" -o tsv 2>$null
            $message = az storage account check-name --name $storageAccountName --query "message" -o tsv 2>$null
            
            Write-Host ""
            Write-Host "❌ ERROR: Storage account name '$storageAccountName' is not available" -ForegroundColor Red
            Write-Host "  Reason: $reason" -ForegroundColor Red
            Write-Host "  Message: $message" -ForegroundColor Red
            Write-Host ""
            Write-Host "💡 Please update the 'scriptStorageAccount' parameter in $ParametersFile with either:" -ForegroundColor Yellow
            Write-Host "   • An empty string ('') to auto-generate a new name" -ForegroundColor Yellow
            Write-Host "   • A different globally unique storage account name" -ForegroundColor Yellow
            Write-Host ""
            exit 1
        }
    }
}

Write-Host "💾 Storage Account: $storageAccountName" -ForegroundColor Cyan
Write-Host ""

# Check if tar command is available for compression
Write-Host "🔍 Checking system requirements..." -ForegroundColor Yellow
try {
    tar --version 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ tar command available for archive compression" -ForegroundColor Green
    } else {
        Write-Warning "⚠️  tar command not found - archives compression may fail"
        Write-Host "💡 On Windows 10/11, tar is usually available. Try running 'tar --version' manually." -ForegroundColor Yellow
    }
} catch {
    Write-Warning "⚠️  Could not verify tar availability - archives compression may fail"
}

# Check if resource group exists, create if it doesn't
Write-Host "🔍 Checking if resource group exists..." -ForegroundColor Yellow
$rgExists = az group exists --name $ResourceGroupName 2>$null
if ($rgExists -eq "false") {
    Write-Host "📁 Creating resource group: $ResourceGroupName" -ForegroundColor Yellow
    az group create --name $ResourceGroupName --location $Location --output none 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "❌ Failed to create resource group"
        exit 1
    }
    Write-Host "✅ Resource group created successfully" -ForegroundColor Green
} else {
    Write-Host "✅ Resource group already exists" -ForegroundColor Green
}

# Create or use existing storage account
if ($createNewAccount) {
    # Create storage account with SECURE access (storage account key - no anonymous access)
    Write-Host "💾 Creating storage account with key-based authentication (secure)..." -ForegroundColor Yellow
    az storage account create `
        --name $storageAccountName `
        --resource-group $ResourceGroupName `
        --location $Location `
        --sku Standard_LRS `
        --kind StorageV2 `
        --access-tier Hot `
        --allow-blob-public-access false `
        --min-tls-version TLS1_2 `
        --https-only true `
        --output none 2>$null

    if ($LASTEXITCODE -ne 0) {
        Write-Error "❌ Failed to create storage account"
        exit 1
    }

    Write-Host "✅ Storage account created successfully" -ForegroundColor Green

    # Wait for storage account to be fully ready by polling provisioning state
    Write-Host "⏳ Waiting for storage account to be fully provisioned..." -ForegroundColor Yellow
    $maxAttempts = 30
    $attempt = 0
    $provisioningState = ""
    
    while ($attempt -lt $maxAttempts) {
        $attempt++
        $provisioningState = az storage account show `
            --name $storageAccountName `
            --resource-group $ResourceGroupName `
            --query "provisioningState" -o tsv 2>$null
        
        if ($provisioningState -eq "Succeeded") {
            Write-Host "✅ Storage account is fully provisioned and ready" -ForegroundColor Green
            break
        }
        
        Write-Host "  ⏳ Provisioning state: $provisioningState (attempt $attempt/$maxAttempts)" -ForegroundColor Gray
        Start-Sleep -Seconds 2
    }
    
    if ($provisioningState -ne "Succeeded") {
        Write-Error "❌ Storage account provisioning did not complete in expected time (state: $provisioningState)"
        exit 1
    }
} else {
    Write-Host "♻️  Using existing storage account: $storageAccountName" -ForegroundColor Green
    
    # Disable blob public access on existing account for security
    Write-Host "� Ensuring blob public access is DISABLED for security..." -ForegroundColor Yellow
    az storage account update `
        --name $storageAccountName `
        --resource-group $ResourceGroupName `
        --allow-blob-public-access false `
        --output none 2>$null

    if ($LASTEXITCODE -ne 0) {
        Write-Warning "⚠️  Warning: Failed to update blob public access setting"
    } else {
        Write-Host "✅ Storage account configured for key-based authentication" -ForegroundColor Green
    }
}

# Get storage account key
Write-Host "🔑 Retrieving storage account key..." -ForegroundColor Yellow
$storageKey = az storage account keys list --account-name $storageAccountName --resource-group $ResourceGroupName --query '[0].value' -o tsv

if (-not $storageKey) {
    Write-Error "❌ Failed to get storage account key"
    exit 1
}

# Create or verify container with PRIVATE access (key-based authentication)
Write-Host "📦 Creating/verifying container with private access..." -ForegroundColor Yellow

# Check if container exists
$containerExists = az storage container exists `
    --name $ContainerName `
    --account-name $storageAccountName `
    --account-key $storageKey `
    --query "exists" -o tsv 2>$null

if ($containerExists -eq "true") {
    Write-Host "  ✅ Container already exists" -ForegroundColor Green
} else {
    az storage container create `
        --name $ContainerName `
        --account-name $storageAccountName `
        --account-key $storageKey `
        --public-access off `
        --output none 2>$null

    if ($LASTEXITCODE -ne 0) {
        Write-Error "❌ Failed to create container"
        exit 1
    }
    Write-Host "  ✅ Container created successfully with private access" -ForegroundColor Green
}

# Ensure container public access is disabled for security
Write-Host "� Ensuring container has private access (no anonymous access)..." -ForegroundColor Yellow
az storage container set-permission `
    --name $ContainerName `
    --account-name $storageAccountName `
    --account-key $storageKey `
    --public-access off `
    --output none 2>$null

if ($LASTEXITCODE -ne 0) {
    Write-Warning "⚠️  Warning: Failed to set container permissions"
}

# Verify the private access setting
$publicAccess = az storage container show `
    --name $ContainerName `
    --account-name $storageAccountName `
    --account-key $storageKey `
    --query "properties.publicAccess" -o tsv

if ($publicAccess -eq "None" -or [string]::IsNullOrEmpty($publicAccess)) {
    Write-Host "✅ Container configured with private access (key-based authentication)" -ForegroundColor Green
} else {
    Write-Warning "⚠️  Warning: Container may still have public access enabled (got: $publicAccess)"
}

# Upload all assets from upload directory with special handling for archives
Write-Host "📤 Uploading deployment assets..." -ForegroundColor Yellow

if (-not (Test-Path $UploadAssetsPath)) {
    Write-Error "❌ Upload assets directory not found: $UploadAssetsPath"
    Write-Host "💡 Please ensure the assets directory exists and contains your deployment files" -ForegroundColor Yellow
    exit 1
}

# Create a temporary directory for processing
$tempDir = Join-Path $env:TEMP "predeploy-temp-$(Get-Random)"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
Write-Host "📁 Created temporary directory: $tempDir" -ForegroundColor Gray

try {
    # Check for archives directory and compress subfolders
    $archivesPath = Join-Path $UploadAssetsPath "archives"
    if (Test-Path $archivesPath) {
        Write-Host "🗜️  Processing archives directory..." -ForegroundColor Yellow
        
        $archiveSubfolders = Get-ChildItem -Path $archivesPath -Directory
        if ($archiveSubfolders.Count -gt 0) {
            Write-Host "📦 Found $($archiveSubfolders.Count) subfolders to compress:" -ForegroundColor Cyan
            
            foreach ($subfolder in $archiveSubfolders) {
                $archiveName = "$($subfolder.Name).tar.gz"
                $archiveDestPath = Join-Path $tempDir $archiveName
                
                Write-Host "  🗜️  Compressing $($subfolder.Name) -> $archiveName" -ForegroundColor Gray
                
                # Use tar command to create compressed archive
                $tarCommand = "tar -czf `"$archiveDestPath`" -C `"$($subfolder.FullName)`" ."
                Invoke-Expression $tarCommand
                
                if ($LASTEXITCODE -ne 0) {
                    Write-Warning "⚠️  Failed to compress $($subfolder.Name)"
                } else {
                    Write-Host "    ✅ Created: $archiveName" -ForegroundColor Green
                }
            }
        }
    }

    # Copy all other files and directories EXCEPT the archives directory
    Write-Host "📋 Copying other files (excluding archives directory)..." -ForegroundColor Yellow
    
    # Get all files from assets directory except anything under the archives subdirectory
    $otherFiles = Get-ChildItem -Path $UploadAssetsPath -Recurse -File | Where-Object {
        $relativePath = $_.FullName.Substring((Resolve-Path $UploadAssetsPath).Path.Length + 1)
        -not $relativePath.StartsWith("archives" + [IO.Path]::DirectorySeparatorChar) -and
        -not $relativePath.StartsWith("archives/")
    }
    
    Write-Host "  📁 Excluding archives directory and its contents from individual file upload" -ForegroundColor Gray
    Write-Host "  📋 Found $($otherFiles.Count) non-archive files to upload" -ForegroundColor Cyan
    
    foreach ($file in $otherFiles) {
        $relativePath = $file.FullName.Substring((Resolve-Path $UploadAssetsPath).Path.Length + 1)
        $destPath = Join-Path $tempDir $relativePath
        $destDir = Split-Path $destPath -Parent
        
        if (-not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }
        
        Copy-Item $file.FullName $destPath
        Write-Host "  � $relativePath" -ForegroundColor Gray
    }

    # Get all files in temp directory to show what will be uploaded
    $assetFiles = Get-ChildItem -Path $tempDir -File -Recurse
    if ($assetFiles.Count -eq 0) {
        Write-Warning "⚠️  No files found to upload"
        exit 1
    }

    Write-Host "📋 Final upload list ($($assetFiles.Count) files):" -ForegroundColor Cyan
    $fullTempPath = (Resolve-Path $tempDir).Path
    foreach ($file in $assetFiles) {
        $relativePath = $file.FullName.Substring($fullTempPath.Length + 1).Replace('\', '/')
        Write-Host "  • $relativePath" -ForegroundColor Gray
    }
    Write-Host ""

    # Use batch upload for much faster performance (uploads in parallel)
    Write-Host "⚡ Batch uploading all processed assets..." -ForegroundColor Cyan
    az storage blob upload-batch `
        --account-name $storageAccountName `
        --account-key $storageKey `
        --destination $ContainerName `
        --source $tempDir `
        --overwrite `
        --pattern "*" `
        --content-type "application/octet-stream" `
        --output none 2>$null

    if ($LASTEXITCODE -ne 0) {
        Write-Error "❌ Failed to batch upload assets"
        exit 1
    }

    Write-Host "✅ All assets uploaded successfully via batch upload" -ForegroundColor Green

} finally {
    # Clean up temporary directory
    if (Test-Path $tempDir) {
        Remove-Item -Path $tempDir -Recurse -Force
        Write-Host "🧹 Cleaned up temporary directory" -ForegroundColor Gray
    }
}

# Update main.bicepparam file
Write-Host "📝 Updating parameters file: $ParametersFile" -ForegroundColor Yellow

if (-not (Test-Path $ParametersFile)) {
    Write-Error "❌ Parameters file not found: $ParametersFile"
    exit 1
}

# Read current parameters file
$paramContent = Get-Content $ParametersFile -Raw
$parameterUpdated = $false

# Check if scriptStorageAccount parameter already exists
if ($paramContent -match "param scriptStorageAccount = '([^']*)'") {
    $currentValue = $Matches[1]
    if ($currentValue -ne $storageAccountName) {
        # Update existing parameter
        $paramContent = $paramContent -replace "param scriptStorageAccount = '.*'", "param scriptStorageAccount = '$storageAccountName'"
        Write-Host "  ✏️  Updated scriptStorageAccount parameter: '$currentValue' -> '$storageAccountName'" -ForegroundColor Cyan
        $parameterUpdated = $true
    } else {
        Write-Host "  ✅ scriptStorageAccount parameter already contains correct value: '$storageAccountName'" -ForegroundColor Green
    }
} else {
    # Add new parameter after the existing Azure Stack HCI configuration
    $insertPoint = $paramContent.IndexOf("param vmImageName")
    if ($insertPoint -gt 0) {
        $beforeInsert = $paramContent.Substring(0, $insertPoint)
        $afterInsert = $paramContent.Substring($insertPoint)
        $paramContent = $beforeInsert + "param scriptStorageAccount = '$storageAccountName'`n" + $afterInsert
        Write-Host "  ➕ Added new scriptStorageAccount parameter with value: '$storageAccountName'" -ForegroundColor Cyan
        $parameterUpdated = $true
    } else {
        # Fallback: append at the end of Azure configuration section
        $vmImageLine = ($paramContent -split "`n" | Where-Object { $_ -match "param vmImageName" })[0]
        $paramContent = $paramContent -replace [regex]::Escape($vmImageLine), "$vmImageLine`nparam scriptStorageAccount = '$storageAccountName'"
        Write-Host "  ➕ Added new scriptStorageAccount parameter with value: '$storageAccountName' (fallback)" -ForegroundColor Cyan
        $parameterUpdated = $true
    }
}

# Write updated content back to file only if changes were made
if ($parameterUpdated) {
    $paramContent | Set-Content $ParametersFile -NoNewline
    Write-Host "✅ Parameters file updated successfully" -ForegroundColor Green
} else {
    Write-Host "✅ Parameters file already up to date" -ForegroundColor Green
}
Write-Host ""

# Summary
Write-Host "🎉 Step 1 Complete! Storage Account Setup and Asset Upload Successful" -ForegroundColor Green
Write-Host ""
Write-Host "📋 Summary:" -ForegroundColor White
Write-Host "  💾 Storage Account: $storageAccountName" -ForegroundColor Cyan
Write-Host "  📦 Container: $ContainerName" -ForegroundColor Cyan
Write-Host "  🚫 Anonymous Access: DISABLED" -ForegroundColor Green
Write-Host "  📄 Assets Uploaded: $($uploadedAssets.Count)" -ForegroundColor Cyan
Write-Host "  ✅ All assets processed and uploaded successfully!" -ForegroundColor Green
Write-Host "  📝 Parameters File Updated: $ParametersFile" -ForegroundColor Cyan
Write-Host ""
Write-Host "🚀 Next Step: Run your Bicep deployment" -ForegroundColor Yellow
Write-Host "   Basic deployment (password authentication):" -ForegroundColor Cyan
Write-Host "az deployment group create --resource-group `"$ResourceGroupName`" --template-file `"infra/main.bicep`" --parameters `"$ParametersFile`"" -ForegroundColor Gray
Write-Host ""
Write-Host "   With SSH key (password + SSH authentication):" -ForegroundColor Cyan
Write-Host "`$sshKey = Get-Content `"`$env:USERPROFILE\.ssh\id_rsa.pub`" -Raw" -ForegroundColor Gray
Write-Host "az deployment group create --resource-group `"$ResourceGroupName`" --template-file `"infra/main.bicep`" --parameters `"$ParametersFile`" --parameters sshPublicKey=`"`$sshKey`"" -ForegroundColor Gray
Write-Host ""