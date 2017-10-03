
Param(
    [Parameter(Mandatory=$True)]
    [string]$accessToken,
    [switch]$updateRelease  #pass "-updateRelease" as a parameter to script if you want to actually update the release definiton
)

function Test-ReleaseDefinition {
    param([parameter(Mandatory=$True)]
    [PSCustomObject]$releaseDefinitionDetail)

    #loop through all the environments in the release definition    
    foreach($environment in $releaseDefinitionDetail.environments){

        #only want to update the "Merge" environment.  Separate report shows that there is max of one environment per release definition with that name
        if ($environment.name -eq $environmentName) {
            
            #Inspect and set default values for the environment
            if ($environment.owner.id -ne $environmentOwner -or
                $environment.name -cne $environmentName -or
                $environment.environmentOptions.emailNotificationType -ne $notificationType -or
                $environment.environmentOptions.emailRecipients -ne $emailRecipients -or
                $environment.deployPhases[0].deploymentInput.skipArtifactsDownload -ne $True -or
                $environment.deployPhases[0].deploymentInput.queueId -ne $QueueID -or
                $environment.deployPhases.workflowTasks[0].inputs.TargetTag -ne $TargetTag) {

                    $script:updated++
                    Write-LogInfo -LogPath $logPath -Message "Release Definition $script:relName $script:logText"
            }
            else {
                $script:skipped++
                Write-LogInfo -LogPath $logPath -Message "Release Definition $script:relName configured correctly"
            }
        }
    }
}

function Update-ReleaseDefinition {
    param([parameter(Mandatory=$True)]
    [PSCustomObject]$releaseDefinitionDetail)

    #loop through all the environments in the release definition    
    foreach($environment in $releaseDefinitionDetail.environments){

        #only want to update the "Merge" environment.  Separate report shows that there is max of one environment per release definition with that name
        if ($environment.name -eq $environmentName) {
            
            #Inspect and set default values for the environment
            if ($environment.owner.id -ne $environmentOwner -or
                $environment.name -cne $environmentName -or
                $environment.environmentOptions.emailNotificationType -ne $notificationType -or
                $environment.environmentOptions.emailRecipients -ne $emailRecipients -or
                $environment.deployPhases[0].deploymentInput.skipArtifactsDownload -ne $True -or
                $environment.deployPhases[0].deploymentInput.queueId -ne $QueueID -or
                $environment.deployPhases.workflowTasks[0].inputs.TargetTag -ne $TargetTag) {
                $needsUpdate = $True
                break
            }
        }
    }
    
    if ($needsUpdate) {
        #update release definition
        try {
            $environment.owner.id = $environmentOwner
            $environment.name = $environmentName
            $environment.environmentOptions.emailNotificationType = $notificationType
            $environment.environmentOptions.emailRecipients = $emailRecipients
            $environment.deployPhases[0].deploymentInput.skipArtifactsDownload = $true
            $environment.deployPhases[0].deploymentInput.queueId = $QueueID
            $environment.deployPhases.workflowTasks[0].inputs.TargetTag = $TargetTag
            
            $PayloadJson = $releaseDefinitionDetail | ConvertTo-Json -Depth 15 -Compress
            
            $UpdateRelDefDetailsUri = "https://adesacentral.vsrm.visualstudio.com/Adesa/_apis/release/definitions/?api-version=4.0-preview.3"
            $UpdateReleaseDef = Invoke-WebRequest -Method 'PUT' -Uri $UpdateRelDefDetailsUri -ContentType 'application/json' -Headers @{Authorization = $AuthorizationHeader} -Body $PayloadJson
            
            $script:updated++
            Write-LogInfo -LogPath $logPath -Message "Release Definition $script:relName $script:logText"
        }
        catch {
            Write-LogError -LogPath $logPath -Message "Fail to update Release Definition $script:relName!" 
            Write-LogError -LogPath $logPath -Message "StatusCode:" $_.Exception.Response.StatusCode.value 
            Write-LogError -LogPath $logPath -Message "StatusDescription:" $_.Exception.Response.StatusDescription
            Write-LogError -LogPath $logPath -Message "UpdateReleaseDef Response:" $UpdateReleaseDef
        }
    }
    else {
        $script:skipped++
        Write-LogInfo -LogPath $logPath -Message "Release Definition $script:relName configured correctly"
    }
}

#*********************************************************************************************************************
#       Entry point of module
#*********************************************************************************************************************
#need to install logging module from PSGallery: Install-Module -Name PSLogging -Scope CurrentUser
Import-Module PSLogging

#log preamble
if ($updateRelease) {
    Start-Log -LogPath "C:\temp" -LogName "SetMergeEnvironmentDefaults.log" -ScriptVersion "1.0"
    $logPath = "C:\temp\SetMergeEnvironmentDefaults.log"
    $logText = "was/were updated"
} else {
    Start-Log -LogPath "C:\temp" -LogName "SetMergeEnvironmentDefaults-Verify.log" -ScriptVersion "1.0"
    $logPath = "C:\temp\SetMergeEnvironmentDefaults-Verify.log"
    $logText = "needs updating"
    }

Write-LogInfo -LogPath $logPath -Message " "
Write-LogInfo -LogPath $logPath -Message "***************************************************************************************************"
Write-LogInfo -LogPath $logPath -Message "                         Standardize Merge Environment Default Values"
Write-LogInfo -LogPath $logPath -Message "***************************************************************************************************"
Write-LogInfo -LogPath $logPath -Message " "

#Build Auth Header
$Password = ":$($accessToken)"
$EncodedCredentials = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($Password))
$AuthorizationHeader = "Basic $EncodedCredentials"

#initalize variables and constants
$updated = 0
$skipped = 0
$environmentOwner = "abbc890e-c0ab-43eb-84ec-11b6b6df3449" #need elevated permissions to retrieve [ADESA]\DevOps account info (guid = "abbc890e-c0ab-43eb-84ec-11b6b6df3449")
$environmentName = "Merge"
$notificationType = "OnlyOnFailure"
$emailRecipients = "release.environment.owner;release.creator"
$QueueID = 106 #agent queue "adesa-azure"
$TargetTag = 'V$(Build.BuildNumber)'

#log what is being updated
Write-LogInfo -LogPath $logPath -Message " Configuration to be validated:"
Write-LogInfo -LogPath $logPath -Message "      Environment Owner           =>  [ADESA]\\DevOps"
Write-LogInfo -LogPath $logPath -Message "      Environment Name            =>  $environmentName"
Write-LogInfo -LogPath $logPath -Message "      Email Notification Type     =>  $notificationType"
Write-LogInfo -LogPath $logPath -Message "      Email Recipients            =>  $emailRecipients"
Write-LogInfo -LogPath $logPath -Message "      Agent Queue for Merge Env   =>  adesa-azure"
Write-LogInfo -LogPath $logPath -Message "      Skip Artifact Download      =>  True"
Write-LogInfo -LogPath $logPath -Message "      Target Tag default value"
Write-LogInfo -LogPath $logPath -Message "      Git Auto Merge task         =>  $TargetTag"
Write-LogInfo -LogPath $logPath -Message " "
Write-LogInfo -LogPath $logPath -Message "***************************************************************************************************"
Write-LogInfo -LogPath $logPath -Message " "

#Get list of release definitions
$getRelDefsUri = "https://adesacentral.vsrm.visualstudio.com/DefaultCollection/Adesa/_apis/release/definitions?api-version=3.0-preview.1"
$releaseDefinitions = Invoke-RestMethod -Method 'GET' -Uri $getRelDefsUri -ContentType 'application/json' -Headers @{Authorization = $AuthorizationHeader}

foreach($releaseDefinition in $releaseDefinitions.value){  
    #initialize holding variable
    $releaseDefinitionDetail = $null

    #get release definition details (environments)
    $getRelDefDetailsUri = "https://adesacentral.vsrm.visualstudio.com/Adesa/_apis/release/definitions/$($releaseDefinition.id)?api-version=4.0-preview.3"
    $releaseDefinitionDetail = Invoke-RestMethod -Method 'GET' -Uri $getRelDefDetailsUri -ContentType 'application/json' -Headers @{Authorization = $AuthorizationHeader}

    $needsUpdate = $false
    $relName = $releaseDefinitionDetail.name

    #test to see if updates are necessary for the release definition
    if ($updateRelease) {
        Update-ReleaseDefinition -releaseDefinitionDetail $releaseDefinitionDetail
    }
    else {
        Test-ReleaseDefinition -releaseDefinitionDetail $releaseDefinitionDetail
    }
}

#Finish and output log
Write-LogInfo -LogPath $logPath -Message " "
Write-LogInfo -LogPath $logPath -Message "***************************************************************************************************"
Write-LogInfo -LogPath $logPath -Message "$updated Release Definitions $logText."   
Write-LogInfo -LogPath $logPath -Message "$skipped Release Definitions were skipped."
Write-LogInfo -LogPath $logPath -Message "***************************************************************************************************"
Write-LogInfo -LogPath $logPath -Message " "

Stop-Log -LogPath $logPath 

exit