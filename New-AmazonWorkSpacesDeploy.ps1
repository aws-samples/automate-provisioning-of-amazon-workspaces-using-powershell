<#
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 * SPDX-License-Identifier: MIT-0
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy of this
 * software and associated documentation files (the "Software"), to deal in the Software
 * without restriction, including without limitation the rights to use, copy, modify,
 * merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
 * INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
 * PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 * HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
 * OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 * SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 #>

#Prompting for a path to store logs with a default path provided and normalizes path with trailing \ if not present
$defaultlogpath = "C:\temp\"
if (!($logpath = Read-Host "Path to store WorkSpaces creation log output: [$defaultlogpath]")) { $logpath = $defaultlogpath }
if($logpath -notmatch '\\$') {$logpath = $logpath + "\"}
If(!(test-path $logpath)){$createfolder = New-Item -ItemType Directory -Path $logpath}

#------------------------------------------------------------------------
#Query Active Directory based on user input to get the AD Group for which WorkSpaces will be provisioned
$MyADGroup = Read-Host -Prompt "`n`nEnter the AD Group name for which you want to create WorkSpaces"

Try
{
    $Users = Get-ADGroupMember $MyADGroup | where-object {$_.objectclass -eq 'User'} | Get-ADUser -Properties enabled | Where-Object {$_.enabled -eq $true} | Select-Object SamAccountName
}
Catch
{
    $ErrorMessage = $_.Exception.Message
    $FailedItem = $_.Exception.ItemName
    Write-host $ErrorMessage
    Write-host $FailedItem
    Break
}

$Prompt = "Do you want to create " + $Users.SamAccountName.count + " user WorkSpaces? (Y/N)"
$Proceed = Read-Host -Prompt $Prompt

if($Proceed -eq "Y") {
    write-host "Answered Y so proceeding to next steps"
 }elseif($Proceed -eq "N") {
    write-host "Answered N please run script again and answer Y to proceed"
    Break
 }else {
    write-host "You did not select Y or N"
    Break
 }

#------------------------------------------------------------------------

#Define / list the regions that WorkSpaces are supported in
$WorkSpacesRegions = "us-east-1", `
"us-west-2",`
"ap-northeast-2",`
"ap-southeast-1",`
"ap-southeast-2",`
"ap-northeast-1",`
"ca-central-1",`
"eu-central-1",`
"eu-west-1",`
"eu-west-2",`
"sa-east-1"

Do {
    Write-Host "`n`n`nHere are the WorkSpaces supported regions:"
    $WorkSpacesRegions | sort
    $MyRegion = Read-Host -Prompt 'Type the region identifier to use for provisioning'
    }
    While (-not ($WorkSpacesRegions | Where-Object {$_ -eq $MyRegion}))
Write-host "Region" $MyRegion "selected."    


#------------------------------------------------------------------------
$Directories = Get-DSDirectory -Region $MyRegion | Select-Object DirectoryId, Alias, DNSIpAddrs, Edition, Name, Type

if($Directories.DirectoryId.count -ge 1) {    
    Do {
        Write-Host "`n`n`nHere are the Directories in that region:"
        $Directories | Select-Object DirectoryId, Name, Type, Edition | Format-Table
        $MyDirectory = Read-Host -Prompt 'Type the DirectoryId of the directory to use for provisioning'
        }
        While (-not ($Directories | Where-Object {$_.DirectoryId -eq $MyDirectory}))
    Write-host "Directory" $MyDirectory "selected."

 }else {
    write-host "`n`n`nYou do not have a Directory registered in this region.  See below for instructions to register a Directory"
    write-host "https://docs.aws.amazon.com/workspaces/latest/adminguide/register-deregister-directory.html`n`n`n"
    Break
 }

#------------------------------------------------------------------------

#Query the bundles personal and publicly available from AWS to compare the bundle input by the user against
$MyBundles = Get-WKSWorkspaceBundle -Region $MyRegion | Select-Object BundleId, ImageId, Name, Owner
$AWSBundles = Get-WKSWorkspaceBundle -Owner Amazon -Region $MyRegion | Where-Object {$_.Name -notlike '*Win*7*'} | Select-Object BundleId, ImageId, Name, Owner
$AllBundles = $AWSBundles + $MyBundles


Do {
    Write-Host "`n`n`nHere are the WorkSpace Bundles in that region:"
    $AllBundles  | sort Owner -Descending | sort Name | Select-Object * | Format-Table
    $SelectedBundleId = Read-Host -Prompt 'Type the BundleId of the bundle to use for provisioning'
    }
    While (-not ($AllBundles | Where-Object {$_.BundleId -eq $SelectedBundleId}))
Write-host "BundleId" $SelectedBundleId "selected."    

#------------------------------------------------------------------------

#Prompting for running mode
[Amazon.WorkSpaces.Model.WorkspaceProperties] $WorkspaceProperties = New-object -TypeName Amazon.WorkSpaces.Model.WorkspaceProperties
$defaultrunningmode = "ALWAYS_ON"
$defaultrunningmodetimeout = "60"
$runningmodetimeoutvalues = 1..2880 |Where-Object {$_ % 60 -eq 0}

Do {
    if (!($UserRunningMode = Read-Host "Choose a running mode either AUTO_STOP or ALWAYS_ON: [$defaultrunningmode]")) { $UserRunningMode = $defaultrunningmode }
    }
    While (-not ($UserRunningMode | Where-Object {$_ -eq 'ALWAYS_ON' -or $_ -eq 'AUTO_STOP'}))

if ($UserRunningMode -eq 'AUTO_STOP'){
Do {
    if (!($userrunningmodetimeout = Read-Host "Choose an AUTO_STOP timeout value 60-2880 minutes in increments of 60: [$defaultrunningmodetimeout]")) { $userrunningmodetimeout = $defaultrunningmodetimeout }
    }
    While (-not ($userrunningmodetimeout | Where-Object {$_ -in $runningmodetimeoutvalues}))
    
    $WorkspaceProperties.RunningMode = [Amazon.Workspaces.RunningMode]::AUTO_STOP
    $WorkspaceProperties.RunningModeAutoStopTimeoutInMinutes = $userrunningmodetimeout
}

#------------------------------------------------------------------------

ForEach($User in $Users.SamAccountName)
{
    #Create the actual workspaces
    Try
    {
        $result = New-WKSWorkspace -Region $MyRegion -Workspace @{"BundleID" = $SelectedBundleId; "DirectoryId" = $MyDirectory; "UserName" = $User; "WorkspaceProperties" = $WorkspaceProperties}
    }

    Catch
    {
        $ErrorMessage = $_.Exception.Message
        Write-host $ErrorMessage
        $FailedItem = $_.Exception.ItemName
        Write-host $FailedItem
        Break
    }
    $Date = (get-date).ToString("MM-dd-yyyy")
    If ($result.PendingRequests.State -eq 'PENDING') {
        #If the workspace creation is successful output and log user and WorkSpace ID
        "Resource creation for $User is pending with ID:  " + $result.PendingRequests.WorkSpaceId
        $Status = "Resource creation is pending"
        $Status | Select-Object @{Name="Date";Expression={$Date}}, @{Name="Status";Expression={$Status}}, @{Name="User";Expression={$User}}, @{Name="WorkSpaceId";Expression={$result.PendingRequests.WorkSpaceId}} | export-csv ($logpath + "workspaceslog.csv") -notypeinformation -Append
    }

    If ($null -ne $result.FailedRequests.ErrorCode) {
        #If the workspace creation is failed output and log user and reason
        "Resource creation for $User failed with message:  " + $result.FailedRequests.ErrorMessage
        $Status = "Resource creation failed"
        $Status | Select-Object @{Name="Date";Expression={$Date}}, @{Name="Status";Expression={$result.FailedRequests.ErrorMessage}}, @{Name="User";Expression={$User}}, @{Name="WorkSpaceId";Expression={$result.PendingRequests.WorkSpaceId}} | export-csv ($logpath + "workspaceslog.csv") -notypeinformation -Append
    }
}

