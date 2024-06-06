#################################################
# Export Pi Hole DNS A Records to Unifi DNS     #
# Written by: Nathan Kasco                      #
# Date: 6/5/2024                                #
#################################################

param(
    [switch]
    $EvaluationOnly,
    [switch]
    $TestRecord
)

function Get-UnifiAuth{
    param($URL,$Username,$Pw)

    #URL should be in this format: https://unifi
    #It will automatically be properly formatted with the endpoint URI
    $URI = "$($URL):443/api/auth/login"

    $jsonbody = @{
        username = $username
        password = $pw
    } | ConvertTo-Json

    $Response = Invoke-WebRequest -Uri $URI -Body $jsonbody -ContentType "application/json" -Method Post -SessionVariable websession

    if($Response.StatusCode -eq 200){
        return $websession
    } else {
        return "Unknown error"
    }
}

function Add-UnifiDNSARecord{
    param($URL,$WebSession,$Key,$Value)

    #Check DNS Entries for potential conflict
    $DNSEntriesBefore = Invoke-RestMethod -Uri "$URL/proxy/network/v2/api/site/default/static-dns/devices" -ContentType "application/json" -WebSession $WebSession

    if($Key -in $DNSEntriesBefore.hostname){
        return "AlreadyPresent"
    } else {
        if($EvaluationOnly){
            return "EvaluationMode"
        } else {
            $JSONBody = @{
                "record_type" = "A"
                "value" = $Value
                "key" = $Key
                "enabled" = $true
            } | ConvertTo-Json
            
            #This seems to be responding with 403 every time, needs more investigation
            $AddResponse = Invoke-RestMethod -Uri "$URL/proxy/network/v2/api/site/default/static-dns" -Body $JSONBody -ContentType "application/json" -Method Post -WebSession $WebSession
            
            #Get updated list of current DNS entries
            $DNSEntries = Invoke-RestMethod -Uri "$URL/proxy/network/v2/api/site/default/static-dns/devices" -ContentType "application/json" -WebSession $WebSession
            
            if($DNSEntries){
                if($Key -in $DNSEntries.hostname){
                    return "Success"
                } else {
                    return "Failure"
                }
            } else {
                return "Failure"
            }
        }
    }
}

function Get-PiHoleDNSData{
    param($URL,$APIToken)

    #URL should just be the base URL (ex. http://pihole), not the complete /admin/api.php URL

    # Define the Pi-hole URL and API token
    $piHoleUrl = "$URL/admin/api.php"
    $apiToken = "$APIToken"
    
    $DNSData = Invoke-RestMethod -Uri "$($piHoleUrl)?customdns&action=get&auth=$apiToken"

    if($DNSData){
        $FormattedDNSData = @{}
        #The data from the API comes back largely unformatted, need to put it into a usable HashTable
        $DNSData.data | ForEach-Object { $FormattedDNSData[$_[0]] = $_[1] }

        return $FormattedDNSData
    } else {
        return "Unknown error"
    }
}

if($EvaluationOnly){
    Write-Warning "*** Running in evaluation only mode, no changes will be made to the Unifi DNS ***"
}

Write-Warning "Note: This tool assumes you only have 1 Unifi site, if you have multiple the default will be used. Press ctrl+c to abort"

if($PSVersionTable.PSEdition -ne "Core"){
    #Skip certificate check for Unifi - Only necessary for PowerShell 5.1
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
} else {
    $PSDefaultParameterValues = @{
        "Invoke-WebRequest:SkipCertificateCheck" = $true
        "Invoke-RestMethod:SkipCertificateCheck" = $true
    }
}

$PiHoleURL = Read-Host "Enter Pi Hole URL (ex. http://pihole)"
$PiHoleAPIToken = Read-Host "Paste Pi Hole API token"
$UnifiURL = Read-Host "Enter Unifi URL (ex. https://unifi)"
$UnifiCredentials = Get-Credential -Message "Enter Unifi account credentials (local account suggested)"
$UnifiUsername = $UnifiCredentials.UserName
$UnifiPassword = $UnifiCredentials.GetNetworkCredential().password

Read-Host "Press enter to continue when ready"

Write-Progress -Activity "Retrieving Pi Hole DNS A Records..."
$DNSData = Get-PiHoleDNSData -URL $PiHoleURL -APIToken $PiHoleAPIToken
Write-Progress -Activity " " -Completed

if($DNSData -and $DNSData -ne "Unknown error"){
    Write-Progress -Activity "Initiating Unifi API session ..."
    $UnifiSession = Get-UnifiAuth -URL $UnifiURL -Username $UnifiUsername -Pw $UnifiPassword
    Write-Progress -Activity " " -Completed

    if($UnifiSession -and $UnifiSession -ne "Unknown error"){
        if($TestRecord){
            Add-UnifiDNSARecord -URL $UnifiURL -WebSession $UnifiSession -Key "test" -Value "192.168.20.21"
        } else {
            $Count = 0
            foreach($ARecord in $DNSData.GetEnumerator()){
                $Count++
                Write-Progress -Activity "Processing DNS Record: $($ARecord.Name) ($Count/$($DNSData.count))"
                $Result = Add-UnifiDNSARecord -URL $UnifiURL -WebSession $UnifiSession -Key $ARecord.Name -Value $ARecord.Value
                if($Result -eq "Failure"){
                    Write-Error "Unable to add $($ARecord.Name)"
                } elseif ($Result -eq "AlreadyPresent"){
                    Write-Host "$($ARecord.Name) is already present in the Unifi DNS"
                } elseif ($Result -eq "Success"){
                    Write-Host "Successfully added $($ARecord.Name) to Unifi DNS" -ForegroundColor Green
                } elseif ($Result -eq "EvaluationMode"){
                    Write-Host "$($ARecord.Name) is not present in the Unifi DNS"
                }
            }
        }
    } else {
        Write-Error "Unable to initiate session with Unifi API, unable to continue"
        Read-Host "Press enter to exit"
        Exit 1603
    }
} else {
    Write-Error "Unable to retrieve data from Pi Hole API, unable to continue"
    Read-Host "Press enter to exit"
    Exit 1603
}