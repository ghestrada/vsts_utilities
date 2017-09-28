<#
    This module was created to update specific parameters in VSTS release definitions that contain the Merge environment.
    While this is a single targetted script, it can be used as a template to apply standardization to other environments.
    
    Originally, the thinking was that the VSTS Rest API to update release definitions could be as lightweight as other update API
    calls.  This is not the case.  As was discovered through a lot of trial and error, it turns out that most of the payload elements
    are required for the API.  Even when that requirement was satisfied, the API still would not honor the request, reporting
    that the release definition was "stale".

    As a result, I reverted the code to return the ENTIRE payload back to the API (with selected edits to update the values that
    I was interested in).  While not the most efficient process, it is effective.

    If you chose to use this as a template to update other release definition environments, the function Update-ReleaseDefinition 
    will require modification to interigate the elements that you are interested in, as well as the variable constants used
    in the comparisons.  Also, change the logging file name.
#>

Param(
    [Parameter(Mandatory=$True)]
    [string]$accessToken,
    [switch]$updateRelease  #pass "-updateRelease" as a parameter to script if you want to actually update the release definiton
)

function Update-ReleaseDefinition {

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
            $script:updated++
            if ($updateRelease) {

                $environment.owner.id = $environmentOwner
                $environment.name = $environmentName
                $environment.environmentOptions.emailNotificationType = $notificationType
                $environment.environmentOptions.emailRecipients = $emailRecipients
                $environment.deployPhases[0].deploymentInput.skipArtifactsDownload = $true
                $environment.deployPhases[0].deploymentInput.queueId = $QueueID
                $environment.deployPhases.workflowTasks[0].inputs.TargetTag = $TargetTag

                <# This block is first attempt to build lightweight payload to only update the release definition elements that we are interested in.
                   Turns out that there are so many required elements, that even when they are all provided, the web service returns "stale definition, please
                   reload and try request again".  Therefore, went back to square one, but this time being explicit with the fully described element names.
                   This was a valuable exercise to figure out how to code a json payload from scratch with both arrays and hashtable objects.

                $DeploymentInputPayload = [pscustomobject]@{deploymentInput=$environment.deployPhases.deploymentInput;
                                            rank=$environment.deployPhases.Rank;phaseType=$environment.deployPhases.phaseType;
                                            name=$environment.deployPhases.name;workflowTasks=@($environment.deployPhases.workflowTasks)}

                $EnvOptionsPayload = [pscustomobject]@{emailNotificationType=$notificationType;emailRecipients=$emailRecipients;skipArtifactsDownload=$True}
                $OwnerPayload = [pscustomobject]@{id=$environmentOwner}
                $EnvironmentPayload = [pscustomobject]@{id=$environment.id;name=$environmentName;owner=$OwnerPayload;
                                                        preDeployApprovals=$environment.preDeployApprovals;postDeployApprovals=$environment.postDeployApprovals;
                                                        deployPhases=@($DeploymentInputPayload);environmentOptions=$EnvOptionsPayload;
                                                        retentionPolicy=$environment.retentionPolicy}
                $Payload = [pscustomobject]@{source="restApi";id=$releaseDefinitionDetail.id;name=$releaseDefinitionDetail.name;
                                             environments=@($EnvironmentPayload)}
                                             
                $PayloadJson = $Payload | ConvertTo-Json -Depth 15 -Compress
                #>

                $PayloadJson = $releaseDefinitionDetail | ConvertTo-Json -Depth 15 -Compress
                
                $UpdateRelDefDetailsUri = "https://adesacentral.vsrm.visualstudio.com/Adesa/_apis/release/definitions/?api-version=4.0-preview.3"
                $UpdateReleaseDef = Invoke-WebRequest -Method 'PUT' -Uri $UpdateRelDefDetailsUri -ContentType 'application/json' -Headers @{Authorization = $AuthorizationHeader} -Body $PayloadJson
                if ($UpdateReleaseDef.StatusCode -eq 200) {
                    Write-LogInfo -LogPath $logPath -Message "Release Definition $relName updated"
                }
            }
            else {
                Write-LogInfo -LogPath $logPath -Message "Release Definition $relName needs updating"
            }
        }
        catch {
            Write-LogError -LogPath $logPath -Message "Fail to update Release Definition $relName!" 
            Write-LogError -LogPath $logPath -Message "StatusCode:" $_.Exception.Response.StatusCode.value 
            Write-LogError -LogPath $logPath -Message "StatusDescription:" $_.Exception.Response.StatusDescription
        }
    }
    else {
        $script:skipped++
        Write-LogInfo -LogPath $logPath -Message "Release Definition $relName configured correctly"
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
} else {
    Start-Log -LogPath "C:\temp" -LogName "SetMergeEnvironmentDefaults-Verify.log" -ScriptVersion "1.0"
    $logPath = "C:\temp\SetMergeEnvironmentDefaults-Verify.log"
    }
Write-LogInfo -LogPath $logPath -Message " "
Write-LogInfo -LogPath $logPath -Message "***************************************************************************************************"
Write-LogInfo -LogPath $logPath -Message "                         Configure Merge Environment Default Values"
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
Write-LogInfo -LogPath $logPath -Message " Updates to be applied:"
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
    Update-ReleaseDefinition 
}

#Finish and output log
Write-LogInfo -LogPath $logPath -Message " "
Write-LogInfo -LogPath $logPath -Message "***************************************************************************************************"

if ($updateRelease) {
    Write-LogInfo -LogPath $logPath -Message "$updated Release Definitions were updated."   
}
else {
    Write-LogInfo -LogPath $logPath -Message "$updated Release Definitions need updating."   
}

Write-LogInfo -LogPath $logPath -Message "$skipped Release Definitions were skipped."
Write-LogInfo -LogPath $logPath -Message "***************************************************************************************************"
Write-LogInfo -LogPath $logPath -Message " "

Stop-Log -LogPath $logPath 

exit