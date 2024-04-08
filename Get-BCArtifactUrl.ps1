# from https://github.com/microsoft/navcontainerhelper/blob/master/Artifacts/Get-BCArtifactUrl.ps1

<# 
 .Synopsis
  Get a list of available artifact URLs
 .Description
  Get a list of available artifact URLs.  It can be used to create a new instance of a Container.
 .Parameter type
  OnPrem or Sandbox (default is Sandbox)
 .Parameter country
  the requested localization of Business Central
 .Parameter version
  The version of Business Central (will search for entries where the version starts with this value of the parameter)
 .Parameter select
  All or only the latest (Default Latest):
    - All: will return all possible urls in the selection.
    - Latest: will sort on version, and return latest version.
    - Daily: will return the latest build from yesterday (ignoring builds from today). Daily only works with Sandbox artifacts.
    - Weekly: will return the latest build from last week (ignoring builds from this wwek). Weekly only works with Sandbox artifacts.
    - Closest: will return the closest version to the version specified in version (must be a full version number).
    - SecondToLastMajor: will return the latest version where Major version number is second to Last (used to get Next Minor version from insider).
    - Current: will return the currently active sandbox release.
    - NextMajor: will return the next major sandbox release (will return empty if no Next Major is available).
    - NextMinor: will return the next minor sandbox release (will return NextMajor when the next release is a major release).
 .Parameter storageAccount
  The storageAccount that is being used where artifacts are stored (default is bcartifacts, usually should not be changed).
 .Parameter sasToken
  OBSOLETE - sasToken is no longer supported
 .Parameter accept_insiderEula
  Accept the EULA for Business Central Insider artifacts. This is required for using Business Central Insider artifacts without providing a SAS token after October 1st 2023.
 .Example
  Get the latest URL for Belgium: 
  Get-BCArtifactUrl -Type OnPrem -Select Latest -country be
  
  Get all available Artifact URLs for BC SaaS:
  Get-BCArtifactUrl -Type Sandbox -Select All
#>
function Get-BCArtifactUrl {
    [CmdletBinding()]
    param (
        [ValidateSet('OnPrem', 'Sandbox')]
        [String] $type = 'Sandbox',
        [String] $country = '',
        [String] $version = '',
        [ValidateSet('Latest', 'First', 'All', 'Closest', 'SecondToLastMajor', 'Current', 'NextMinor', 'NextMajor', 'Daily', 'Weekly')]
        [String] $select = 'Latest',
        [DateTime] $after,
        [DateTime] $before,
        [String] $storageAccount = '',
        [Obsolete("sasToken is no longer supported")]
        [String] $sasToken = '',
        [switch] $accept_insiderEula,
        [switch] $doNotCheckPlatform
    )

#$telemetryScope = InitTelemetryScope -name $MyInvocation.InvocationName -parameterValues $PSBoundParameters -includeParameters @("type","country","version","select","after","before","StorageAccount")
try {

    if ($type -eq "OnPrem") {
        if ($version -like '18.9*') {
            Write-Host -ForegroundColor Yellow 'On-premises build for 18.9 was replaced by 18.10.35134.0, using this version number instead'
            $version = '18.10.35134.0'
        }
        elseif ($version -like '17.14*') {
            Write-Host -ForegroundColor Yellow 'On-premises build for 17.14 was replaced by 17.15.35135.0, using this version number instead'
            $version = '17.15.35135.0'
        }
        elseif ($version -like '16.18*') {
            Write-Host -ForegroundColor Yellow 'On-premises build for 16.18 was replaced by 16.19.35126.0, using this version number instead'
            $version = '16.19.35126.0'
        }
        if ($select -eq "Weekly" -or $select -eq "Daily") {
            $select = 'Latest'
        }
    }

    if ($select -eq "Weekly" -or $select -eq "Daily") {
        if ($select -eq "Daily") {
            $ignoreBuildsAfter = [DateTime]::Today
        }
        else {
            $ignoreBuildsAfter = [DateTime]::Today.AddDays(-[datetime]::Today.DayOfWeek)
        }
        if ($version -ne '' -or ($after) -or ($before)) {
            throw 'You cannot specify version, before or after  when selecting Daily or Weekly build'
        }
        $current = Get-BCArtifactUrl -country $country -select Latest -doNotCheckPlatform:$doNotCheckPlatform
        Write-Verbose "Current build is $current"
        if ($current) {
            $currentversion = [System.Version]($current.Split('/')[4])
            $periodic = Get-BCArtifactUrl -country $country -select Latest -doNotCheckPlatform:$doNotCheckPlatform -before ($ignoreBuildsAfter.ToUniversalTime()) -version "$($currentversion.Major).$($currentversion.Minor)"
            if (-not $periodic) {
                $periodic = Get-BCArtifactUrl -country $country -select First -doNotCheckPlatform:$doNotCheckPlatform -after ($ignoreBuildsAfter.ToUniversalTime()) -version "$($currentversion.Major).$($currentversion.Minor)"
            }
            Write-Verbose "Periodic build is $periodic"
            if ($periodic) { $current = $periodic }
        }
        $current
    }
    elseif ($select -eq "Current") {
        if ($storageAccount -ne '' -or $type -eq 'OnPrem' -or $version -ne '') {
            throw 'You cannot specify storageAccount, type=OnPrem or version when selecting Current release'
        }
        Get-BCArtifactUrl -country $country -select Latest -doNotCheckPlatform:$doNotCheckPlatform
    }
    elseif ($select -eq "NextMinor" -or $select -eq "NextMajor") {
        if ($storageAccount -ne '' -or $type -eq 'OnPrem' -or $version -ne '') {
            throw "You cannot specify storageAccount, type=OnPrem or version when selecting $select release"
        }

        $current = Get-BCArtifactUrl -country 'base' -select Latest -doNotCheckPlatform:$doNotCheckPlatform
        $currentversion = [System.Version]($current.Split('/')[4])

        $nextminorversion = "$($currentversion.Major).$($currentversion.Minor+1)."
        $nextmajorversion = "$($currentversion.Major+1).0."
        if ($currentVersion.Minor -ge 5) {
            $nextminorversion = $nextmajorversion
        }

        if (-not $country) { $country = 'w1' }
        $insiders = Get-BcArtifactUrl -country $country -storageAccount bcinsider -select All -doNotCheckPlatform:$doNotCheckPlatform -accept_insiderEula:$accept_insiderEula
        $nextmajor = $insiders | Where-Object { $_.Split('/')[4].StartsWith($nextmajorversion) } | Select-Object -Last 1
        $nextminor = $insiders | Where-Object { $_.Split('/')[4].StartsWith($nextminorversion) } | Select-Object -Last 1

        if ($select -eq 'NextMinor') {
            $nextminor
        }
        else {
            $nextmajor
        }
    }
    else {
        if ($storageAccount -eq '') {
            $storageAccount = 'bcartifacts'
        }

        if (-not $storageAccount.Contains('.')) {
            $storageAccount += ".blob.core.windows.net"
        }
        $BaseUrl = ReplaceCDN -sourceUrl "https://$storageAccount/$($Type.ToLowerInvariant())/" -useBlobUrl:($bcContainerHelperConfig.DoNotUseCdnForArtifacts)
        $storageAccount = ReplaceCDN -sourceUrl $storageAccount -useBlobUrl

        if ($storageAccount -eq 'bcinsider.blob.core.windows.net' -and !$accept_insiderEULA) {
            throw "You need to accept the insider EULA (https://go.microsoft.com/fwlink/?linkid=2245051) by specifying -accept_insiderEula or by providing a SAS token to get access to insider builds"
        }
        $GetListUrl = "https://$storageAccount/$($Type.ToLowerInvariant())/?comp=list&restype=container"
    
        $upMajorFilter = ''
        $upVersionFilter = ''
        if ($select -eq 'SecondToLastMajor') {
            if ($version) {
                throw "You cannot specify a version when asking for the Second To Last Major version"
            }
        }
        elseif ($select -eq 'Closest') {
            if (!($version)) {
                throw "You must specify a version number when you want to get the closest artifact Url"
            }
            $dots = ($version.ToCharArray() -eq '.').Count
            $closestToVersion = [Version]"0.0.0.0"
            if ($dots -ne 3 -or !([Version]::TryParse($version, [ref] $closestToVersion))) {
                throw "Version number must be in the format 1.2.3.4 when you want to get the closes artifact Url"
            }
            $GetListUrl += "&prefix=$($closestToVersion.Major).$($closestToVersion.Minor)."
            $upMajorFilter = "$($closestToVersion.Major)"
            $upVersionFilter = "$($closestToVersion.Minor)."
        }
        elseif (!([string]::IsNullOrEmpty($version))) {
            $dots = ($version.ToCharArray() -eq '.').Count
            if ($dots -lt 3) {
                # avoid 14.1 returning 14.10, 14.11 etc.
                $version = "$($version.TrimEnd('.'))."
            }
            $GetListUrl += "&prefix=$($Version)"
            $upMajorFilter = $version.Split('.')[0]
            $upVersionFilter = $version.Substring($version.Length).TrimStart('.')
        }

        $Artifacts = @()
        $nextMarker = ''
        $currentMarker = ''
        $downloadAttempt = 1
        $downloadRetryAttempts = 10
        do {
            if ($currentMarker -ne $nextMarker)
            {
                $currentMarker = $nextMarker
                $downloadAttempt = 1
            }
            Write-Verbose "Download String $GetListUrl$nextMarker"
            try
            {
                $Response = Invoke-RestMethod -UseBasicParsing -ContentType "application/json; charset=UTF8" -Uri "$GetListUrl$nextMarker"
                if (([int]$Response[0]) -eq 239 -and ([int]$Response[1]) -eq 187 -and ([int]$Response[2]) -eq 191) {
                    # Remove UTF8 BOM
                    $response = $response.Substring(3)
                }
                if (([int]$Response[0]) -eq 65279) {
                    # Remove Unicode BOM (PowerShell 7.4)
                    $response = $response.Substring(1)
                }
                $enumerationResults = ([xml]$Response).EnumerationResults

                if ($enumerationResults.Blobs) {
                    if (($After) -or ($Before)) {
                        $artifacts += $enumerationResults.Blobs.Blob | % {
                            if ($after) {
                                $blobModifiedDate = [DateTime]::Parse($_.Properties."Last-Modified")
                                if ($before) {
                                    if ($blobModifiedDate -lt $before -and $blobModifiedDate -gt $after) {
                                        $_.Name
                                    }
                                }
                                elseif ($blobModifiedDate -gt $after) {
                                    $_.Name
                                }
                            }
                            else {
                                $blobModifiedDate = [DateTime]::Parse($_.Properties."Last-Modified")
                                if ($blobModifiedDate -lt $before) {
                                    $_.Name
                                }
                            }
                        }
                    }
                    else {
                        $artifacts += $enumerationResults.Blobs.Blob.Name
                    }
                }
                $nextMarker = $enumerationResults.NextMarker
                if ($nextMarker) {
                    $nextMarker = "&marker=$nextMarker"
                }
            }
            catch
            {
                $downloadAttempt += 1
                Write-Host "Error querying artifacts. Error message was $($_.Exception.Message)"
                Write-Host

                if ($downloadAttempt -le $downloadRetryAttempts)
                {
                    Write-Host "Repeating download attempt (" $downloadAttempt.ToString() " of " $downloadRetryAttempts.ToString() ")..."
                    Write-Host
                }
                else
                {
                    throw
                }                
            }
        } while ($nextMarker)

        if (!([string]::IsNullOrEmpty($country))) {
            # avoid confusion between base and se
            $countryArtifacts = $Artifacts | Where-Object { $_.EndsWith("/$country", [System.StringComparison]::InvariantCultureIgnoreCase) -and ($doNotCheckPlatform -or ($Artifacts.Contains("$($_.Split('/')[0])/platform"))) }
            if (!$countryArtifacts) {
                if (($type -eq "sandbox") -and ($bcContainerHelperConfig.mapCountryCode.PSObject.Properties.Name -eq $country)) {
                    $country = $bcContainerHelperConfig.mapCountryCode."$country"
                    $countryArtifacts = $Artifacts | Where-Object { $_.EndsWith("/$country", [System.StringComparison]::InvariantCultureIgnoreCase) -and ($doNotCheckPlatform -or ($Artifacts.Contains("$($_.Split('/')[0])/platform"))) }
                }
            }
            $Artifacts = $countryArtifacts
        }
        else {
            $Artifacts = $Artifacts | Where-Object { !($_.EndsWith("/platform", [System.StringComparison]::InvariantCultureIgnoreCase)) }
        }

        switch ($Select) {
            'All' {  
                $Artifacts = $Artifacts |
                    Sort-Object { [Version]($_.Split('/')[0]) }
            }
            'Latest' { 
                $Artifacts = $Artifacts |
                    Sort-Object { [Version]($_.Split('/')[0]) } |
                    Select-Object -Last 1
            }
            'First' { 
                $Artifacts = $Artifacts |
                    Sort-Object { [Version]($_.Split('/')[0]) } |
                    Select-Object -First 1
            }
            'SecondToLastMajor' { 
                $Artifacts = $Artifacts |
                    Sort-Object -Descending { [Version]($_.Split('/')[0]) }
                $latest = $Artifacts | Select-Object -First 1
                if ($latest) {
                    $latestversion = [Version]($latest.Split('/')[0])
                    $Artifacts = $Artifacts |
                        Where-Object { ([Version]($_.Split('/')[0])).Major -ne $latestversion.Major } |
                        Select-Object -First 1
                }
                else {
                    $Artifacts = @()
                }
            }
            'Closest' {
                $Artifacts = $Artifacts |
                    Sort-Object { [Version]($_.Split('/')[0]) }
                $closest = $Artifacts |
                    Where-Object { [Version]($_.Split('/')[0]) -ge $closestToVersion } |
                    Select-Object -First 1
                if (-not $closest) {
                    $closest = $Artifacts | Select-Object -Last 1
                }
                $Artifacts = $closest           
            }
        }
    
        foreach ($Artifact in $Artifacts) {
            "$BaseUrl$($Artifact)$sasToken"
        }
    }
}
catch {
    #TrackException -telemetryScope #$telemetryScope -errorRecord $_
    throw
}
finally {
    #TrackTrace -telemetryScope #$telemetryScope
}
}
#Export-ModuleMember -Function Get-BCArtifactUrl

# SIG # Begin signature block
# MIIr3wYJKoZIhvcNAQcCoIIr0DCCK8wCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDQcFL457umbd+s
# YGNh/ejFZvb4fIY7v2cS2ViocY/7xqCCJPcwggVvMIIEV6ADAgECAhBI/JO0YFWU
# jTanyYqJ1pQWMA0GCSqGSIb3DQEBDAUAMHsxCzAJBgNVBAYTAkdCMRswGQYDVQQI
# DBJHcmVhdGVyIE1hbmNoZXN0ZXIxEDAOBgNVBAcMB1NhbGZvcmQxGjAYBgNVBAoM
# EUNvbW9kbyBDQSBMaW1pdGVkMSEwHwYDVQQDDBhBQUEgQ2VydGlmaWNhdGUgU2Vy
# dmljZXMwHhcNMjEwNTI1MDAwMDAwWhcNMjgxMjMxMjM1OTU5WjBWMQswCQYDVQQG
# EwJHQjEYMBYGA1UEChMPU2VjdGlnbyBMaW1pdGVkMS0wKwYDVQQDEyRTZWN0aWdv
# IFB1YmxpYyBDb2RlIFNpZ25pbmcgUm9vdCBSNDYwggIiMA0GCSqGSIb3DQEBAQUA
# A4ICDwAwggIKAoICAQCN55QSIgQkdC7/FiMCkoq2rjaFrEfUI5ErPtx94jGgUW+s
# hJHjUoq14pbe0IdjJImK/+8Skzt9u7aKvb0Ffyeba2XTpQxpsbxJOZrxbW6q5KCD
# J9qaDStQ6Utbs7hkNqR+Sj2pcaths3OzPAsM79szV+W+NDfjlxtd/R8SPYIDdub7
# P2bSlDFp+m2zNKzBenjcklDyZMeqLQSrw2rq4C+np9xu1+j/2iGrQL+57g2extme
# me/G3h+pDHazJyCh1rr9gOcB0u/rgimVcI3/uxXP/tEPNqIuTzKQdEZrRzUTdwUz
# T2MuuC3hv2WnBGsY2HH6zAjybYmZELGt2z4s5KoYsMYHAXVn3m3pY2MeNn9pib6q
# RT5uWl+PoVvLnTCGMOgDs0DGDQ84zWeoU4j6uDBl+m/H5x2xg3RpPqzEaDux5mcz
# mrYI4IAFSEDu9oJkRqj1c7AGlfJsZZ+/VVscnFcax3hGfHCqlBuCF6yH6bbJDoEc
# QNYWFyn8XJwYK+pF9e+91WdPKF4F7pBMeufG9ND8+s0+MkYTIDaKBOq3qgdGnA2T
# OglmmVhcKaO5DKYwODzQRjY1fJy67sPV+Qp2+n4FG0DKkjXp1XrRtX8ArqmQqsV/
# AZwQsRb8zG4Y3G9i/qZQp7h7uJ0VP/4gDHXIIloTlRmQAOka1cKG8eOO7F/05QID
# AQABo4IBEjCCAQ4wHwYDVR0jBBgwFoAUoBEKIz6W8Qfs4q8p74Klf9AwpLQwHQYD
# VR0OBBYEFDLrkpr/NZZILyhAQnAgNpFcF4XmMA4GA1UdDwEB/wQEAwIBhjAPBgNV
# HRMBAf8EBTADAQH/MBMGA1UdJQQMMAoGCCsGAQUFBwMDMBsGA1UdIAQUMBIwBgYE
# VR0gADAIBgZngQwBBAEwQwYDVR0fBDwwOjA4oDagNIYyaHR0cDovL2NybC5jb21v
# ZG9jYS5jb20vQUFBQ2VydGlmaWNhdGVTZXJ2aWNlcy5jcmwwNAYIKwYBBQUHAQEE
# KDAmMCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5jb21vZG9jYS5jb20wDQYJKoZI
# hvcNAQEMBQADggEBABK/oe+LdJqYRLhpRrWrJAoMpIpnuDqBv0WKfVIHqI0fTiGF
# OaNrXi0ghr8QuK55O1PNtPvYRL4G2VxjZ9RAFodEhnIq1jIV9RKDwvnhXRFAZ/ZC
# J3LFI+ICOBpMIOLbAffNRk8monxmwFE2tokCVMf8WPtsAO7+mKYulaEMUykfb9gZ
# pk+e96wJ6l2CxouvgKe9gUhShDHaMuwV5KZMPWw5c9QLhTkg4IUaaOGnSDip0TYl
# d8GNGRbFiExmfS9jzpjoad+sPKhdnckcW67Y8y90z7h+9teDnRGWYpquRRPaf9xH
# +9/DUp/mBlXpnYzyOmJRvOwkDynUWICE5EV7WtgwggWNMIIEdaADAgECAhAOmxiO
# +dAt5+/bUOIIQBhaMA0GCSqGSIb3DQEBDAUAMGUxCzAJBgNVBAYTAlVTMRUwEwYD
# VQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xJDAi
# BgNVBAMTG0RpZ2lDZXJ0IEFzc3VyZWQgSUQgUm9vdCBDQTAeFw0yMjA4MDEwMDAw
# MDBaFw0zMTExMDkyMzU5NTlaMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdp
# Q2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNVBAMTGERp
# Z2lDZXJ0IFRydXN0ZWQgUm9vdCBHNDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCC
# AgoCggIBAL/mkHNo3rvkXUo8MCIwaTPswqclLskhPfKK2FnC4SmnPVirdprNrnsb
# hA3EMB/zG6Q4FutWxpdtHauyefLKEdLkX9YFPFIPUh/GnhWlfr6fqVcWWVVyr2iT
# cMKyunWZanMylNEQRBAu34LzB4TmdDttceItDBvuINXJIB1jKS3O7F5OyJP4IWGb
# NOsFxl7sWxq868nPzaw0QF+xembud8hIqGZXV59UWI4MK7dPpzDZVu7Ke13jrclP
# XuU15zHL2pNe3I6PgNq2kZhAkHnDeMe2scS1ahg4AxCN2NQ3pC4FfYj1gj4QkXCr
# VYJBMtfbBHMqbpEBfCFM1LyuGwN1XXhm2ToxRJozQL8I11pJpMLmqaBn3aQnvKFP
# ObURWBf3JFxGj2T3wWmIdph2PVldQnaHiZdpekjw4KISG2aadMreSx7nDmOu5tTv
# kpI6nj3cAORFJYm2mkQZK37AlLTSYW3rM9nF30sEAMx9HJXDj/chsrIRt7t/8tWM
# cCxBYKqxYxhElRp2Yn72gLD76GSmM9GJB+G9t+ZDpBi4pncB4Q+UDCEdslQpJYls
# 5Q5SUUd0viastkF13nqsX40/ybzTQRESW+UQUOsxxcpyFiIJ33xMdT9j7CFfxCBR
# a2+xq4aLT8LWRV+dIPyhHsXAj6KxfgommfXkaS+YHS312amyHeUbAgMBAAGjggE6
# MIIBNjAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBTs1+OC0nFdZEzfLmc/57qY
# rhwPTzAfBgNVHSMEGDAWgBRF66Kv9JLLgjEtUYunpyGd823IDzAOBgNVHQ8BAf8E
# BAMCAYYweQYIKwYBBQUHAQEEbTBrMCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5k
# aWdpY2VydC5jb20wQwYIKwYBBQUHMAKGN2h0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0
# LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5jcnQwRQYDVR0fBD4wPDA6oDig
# NoY0aHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElEUm9v
# dENBLmNybDARBgNVHSAECjAIMAYGBFUdIAAwDQYJKoZIhvcNAQEMBQADggEBAHCg
# v0NcVec4X6CjdBs9thbX979XB72arKGHLOyFXqkauyL4hxppVCLtpIh3bb0aFPQT
# SnovLbc47/T/gLn4offyct4kvFIDyE7QKt76LVbP+fT3rDB6mouyXtTP0UNEm0Mh
# 65ZyoUi0mcudT6cGAxN3J0TU53/oWajwvy8LpunyNDzs9wPHh6jSTEAZNUZqaVSw
# uKFWjuyk1T3osdz9HNj0d1pcVIxv76FQPfx2CWiEn2/K2yCNNWAcAgPLILCsWKAO
# QGPFmCLBsln1VWvPJ6tsds5vIy30fnFqI2si/xK4VC0nftg62fC2h5b9W9FcrBjD
# TZ9ztwGpn1eqXijiuZQwggYaMIIEAqADAgECAhBiHW0MUgGeO5B5FSCJIRwKMA0G
# CSqGSIb3DQEBDAUAMFYxCzAJBgNVBAYTAkdCMRgwFgYDVQQKEw9TZWN0aWdvIExp
# bWl0ZWQxLTArBgNVBAMTJFNlY3RpZ28gUHVibGljIENvZGUgU2lnbmluZyBSb290
# IFI0NjAeFw0yMTAzMjIwMDAwMDBaFw0zNjAzMjEyMzU5NTlaMFQxCzAJBgNVBAYT
# AkdCMRgwFgYDVQQKEw9TZWN0aWdvIExpbWl0ZWQxKzApBgNVBAMTIlNlY3RpZ28g
# UHVibGljIENvZGUgU2lnbmluZyBDQSBSMzYwggGiMA0GCSqGSIb3DQEBAQUAA4IB
# jwAwggGKAoIBgQCbK51T+jU/jmAGQ2rAz/V/9shTUxjIztNsfvxYB5UXeWUzCxEe
# AEZGbEN4QMgCsJLZUKhWThj/yPqy0iSZhXkZ6Pg2A2NVDgFigOMYzB2OKhdqfWGV
# oYW3haT29PSTahYkwmMv0b/83nbeECbiMXhSOtbam+/36F09fy1tsB8je/RV0mIk
# 8XL/tfCK6cPuYHE215wzrK0h1SWHTxPbPuYkRdkP05ZwmRmTnAO5/arnY83jeNzh
# P06ShdnRqtZlV59+8yv+KIhE5ILMqgOZYAENHNX9SJDm+qxp4VqpB3MV/h53yl41
# aHU5pledi9lCBbH9JeIkNFICiVHNkRmq4TpxtwfvjsUedyz8rNyfQJy/aOs5b4s+
# ac7IH60B+Ja7TVM+EKv1WuTGwcLmoU3FpOFMbmPj8pz44MPZ1f9+YEQIQty/NQd/
# 2yGgW+ufflcZ/ZE9o1M7a5Jnqf2i2/uMSWymR8r2oQBMdlyh2n5HirY4jKnFH/9g
# Rvd+QOfdRrJZb1sCAwEAAaOCAWQwggFgMB8GA1UdIwQYMBaAFDLrkpr/NZZILyhA
# QnAgNpFcF4XmMB0GA1UdDgQWBBQPKssghyi47G9IritUpimqF6TNDDAOBgNVHQ8B
# Af8EBAMCAYYwEgYDVR0TAQH/BAgwBgEB/wIBADATBgNVHSUEDDAKBggrBgEFBQcD
# AzAbBgNVHSAEFDASMAYGBFUdIAAwCAYGZ4EMAQQBMEsGA1UdHwREMEIwQKA+oDyG
# Omh0dHA6Ly9jcmwuc2VjdGlnby5jb20vU2VjdGlnb1B1YmxpY0NvZGVTaWduaW5n
# Um9vdFI0Ni5jcmwwewYIKwYBBQUHAQEEbzBtMEYGCCsGAQUFBzAChjpodHRwOi8v
# Y3J0LnNlY3RpZ28uY29tL1NlY3RpZ29QdWJsaWNDb2RlU2lnbmluZ1Jvb3RSNDYu
# cDdjMCMGCCsGAQUFBzABhhdodHRwOi8vb2NzcC5zZWN0aWdvLmNvbTANBgkqhkiG
# 9w0BAQwFAAOCAgEABv+C4XdjNm57oRUgmxP/BP6YdURhw1aVcdGRP4Wh60BAscjW
# 4HL9hcpkOTz5jUug2oeunbYAowbFC2AKK+cMcXIBD0ZdOaWTsyNyBBsMLHqafvIh
# rCymlaS98+QpoBCyKppP0OcxYEdU0hpsaqBBIZOtBajjcw5+w/KeFvPYfLF/ldYp
# mlG+vd0xqlqd099iChnyIMvY5HexjO2AmtsbpVn0OhNcWbWDRF/3sBp6fWXhz7Dc
# ML4iTAWS+MVXeNLj1lJziVKEoroGs9Mlizg0bUMbOalOhOfCipnx8CaLZeVme5yE
# Lg09Jlo8BMe80jO37PU8ejfkP9/uPak7VLwELKxAMcJszkyeiaerlphwoKx1uHRz
# NyE6bxuSKcutisqmKL5OTunAvtONEoteSiabkPVSZ2z76mKnzAfZxCl/3dq3dUNw
# 4rg3sTCggkHSRqTqlLMS7gjrhTqBmzu1L90Y1KWN/Y5JKdGvspbOrTfOXyXvmPL6
# E52z1NZJ6ctuMFBQZH3pwWvqURR8AgQdULUvrxjUYbHHj95Ejza63zdrEcxWLDX6
# xWls/GDnVNueKjWUH3fTv1Y8Wdho698YADR7TNx8X8z2Bev6SivBBOHY+uqiirZt
# g0y9ShQoPzmCcn63Syatatvx157YK9hlcPmVoa1oDE5/L9Uo2bC5a4CH2RwwggZZ
# MIIEwaADAgECAhANIM3qwHRbWKHw+Zq6JhzlMA0GCSqGSIb3DQEBDAUAMFQxCzAJ
# BgNVBAYTAkdCMRgwFgYDVQQKEw9TZWN0aWdvIExpbWl0ZWQxKzApBgNVBAMTIlNl
# Y3RpZ28gUHVibGljIENvZGUgU2lnbmluZyBDQSBSMzYwHhcNMjExMDIyMDAwMDAw
# WhcNMjQxMDIxMjM1OTU5WjBdMQswCQYDVQQGEwJESzEUMBIGA1UECAwLSG92ZWRz
# dGFkZW4xGzAZBgNVBAoMEkZyZWRkeSBLcmlzdGlhbnNlbjEbMBkGA1UEAwwSRnJl
# ZGR5IEtyaXN0aWFuc2VuMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA
# gYC5tlg+VRktRRkahxxaV8+DAd6vHoDpcO6w7yT24lnSoMuA6nR7kgy90Y/sHIwK
# E9Wwt/px/GAY8eBePWjJrFpG8fBtJbXadRTVd/470Hs/q9t+kh6A/0ELj7wYsKSN
# OyuFPoy4rtClOv9ZmrRpoDVnh8Epwg2DpklX2BNzykzBQxIbkpp+xVo2mhPNWDIe
# sntc4/BnSebLGw1Vkxmu2acKkIjYrne/7lsuyL9ue0vk8TGk9JBPNPbGKJvHu9sz
# P9oGoH36fU1sEZ+AacXrp+onsyPf/hkkpAMHAhzQHl+5Ikvcus/cDm06twm7Vywm
# Zcas2rFAV5MyE6WMEaYAolwAHiPz9WAs2GDhFtZZg1tzbRjJIIgPpR+doTIcpcDB
# cHnNdSdgWKrTkr2f339oT5bnJfo7oVzc/2HGWvb8Fom6LQAqSC11vWmznHYsCm72
# g+foTKqW8lLDfLF0+aFvToLosrtW9l6Z+l+RQ8MtJ9EHOm2Ny8cFLzZCDZYw32By
# dwcLV5rKdy4Ica9on5xZvyMOLiFwuL4v2V4pjEgKJaGSS/IVSMEGjrM9DHT6YS4/
# oq9q20rQUmMZZQmGmEyyKQ8t11si8VHtScN5m0Li8peoWfCU9mRFxSESwTWow8d4
# 62+o9/SzmDxCACdFwzvfKx4JqDMm55cL+beunIvc0NsCAwEAAaOCAZwwggGYMB8G
# A1UdIwQYMBaAFA8qyyCHKLjsb0iuK1SmKaoXpM0MMB0GA1UdDgQWBBTZD6uy9ZWI
# IqQh3srYu1FlUhdM0TAOBgNVHQ8BAf8EBAMCB4AwDAYDVR0TAQH/BAIwADATBgNV
# HSUEDDAKBggrBgEFBQcDAzARBglghkgBhvhCAQEEBAMCBBAwSgYDVR0gBEMwQTA1
# BgwrBgEEAbIxAQIBAwIwJTAjBggrBgEFBQcCARYXaHR0cHM6Ly9zZWN0aWdvLmNv
# bS9DUFMwCAYGZ4EMAQQBMEkGA1UdHwRCMEAwPqA8oDqGOGh0dHA6Ly9jcmwuc2Vj
# dGlnby5jb20vU2VjdGlnb1B1YmxpY0NvZGVTaWduaW5nQ0FSMzYuY3JsMHkGCCsG
# AQUFBwEBBG0wazBEBggrBgEFBQcwAoY4aHR0cDovL2NydC5zZWN0aWdvLmNvbS9T
# ZWN0aWdvUHVibGljQ29kZVNpZ25pbmdDQVIzNi5jcnQwIwYIKwYBBQUHMAGGF2h0
# dHA6Ly9vY3NwLnNlY3RpZ28uY29tMA0GCSqGSIb3DQEBDAUAA4IBgQASEbZACurQ
# eQN8WDTR+YyNpoQ29YAbbdBRhhzHkT/1ao7LE0QIOgGR4GwKRzufCAwu8pCBiMOU
# TDHTezkh0rQrG6khxBX2nSTBL5i4LwKMR08HgZBsbECciABy15yexYWoB/D0H8Wu
# Ge63PhGWueR4IFPbIz+jEVxfW0Nyyr7bXTecpKd1iprm+TOmzc2E6ab95dkcXdJV
# x6Zys++QrrOfQ+a57qEXkS/wnjjbN9hukL0zg+g8L4DHLKTodzfiQOampvV8Qzbn
# B7Y8YjNcxR9s/nptnlQH3jorNFhktiBXvD62jc8pAIg6wyH6NxSMjtTsn7QhkIp2
# kuswIQwD8hN/fZ/m6gkXZhRJWFr2WRZOz+edZ62Jf25C/NYWscwfBwn2hzRZf1Hg
# yxkXAl88dvvUA3kw1T6uo8aAB9IcL6Owiy7q4T+RLRF7oqx0vcw0193Yhq/gPOaU
# FlqzExP6TQ5TR9XWVPQk+a1B1ATKMLi1JShO6KWTmNkFkgkgpkW69BEwggauMIIE
# lqADAgECAhAHNje3JFR82Ees/ShmKl5bMA0GCSqGSIb3DQEBCwUAMGIxCzAJBgNV
# BAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdp
# Y2VydC5jb20xITAfBgNVBAMTGERpZ2lDZXJ0IFRydXN0ZWQgUm9vdCBHNDAeFw0y
# MjAzMjMwMDAwMDBaFw0zNzAzMjIyMzU5NTlaMGMxCzAJBgNVBAYTAlVTMRcwFQYD
# VQQKEw5EaWdpQ2VydCwgSW5jLjE7MDkGA1UEAxMyRGlnaUNlcnQgVHJ1c3RlZCBH
# NCBSU0E0MDk2IFNIQTI1NiBUaW1lU3RhbXBpbmcgQ0EwggIiMA0GCSqGSIb3DQEB
# AQUAA4ICDwAwggIKAoICAQDGhjUGSbPBPXJJUVXHJQPE8pE3qZdRodbSg9GeTKJt
# oLDMg/la9hGhRBVCX6SI82j6ffOciQt/nR+eDzMfUBMLJnOWbfhXqAJ9/UO0hNoR
# 8XOxs+4rgISKIhjf69o9xBd/qxkrPkLcZ47qUT3w1lbU5ygt69OxtXXnHwZljZQp
# 09nsad/ZkIdGAHvbREGJ3HxqV3rwN3mfXazL6IRktFLydkf3YYMZ3V+0VAshaG43
# IbtArF+y3kp9zvU5EmfvDqVjbOSmxR3NNg1c1eYbqMFkdECnwHLFuk4fsbVYTXn+
# 149zk6wsOeKlSNbwsDETqVcplicu9Yemj052FVUmcJgmf6AaRyBD40NjgHt1bicl
# kJg6OBGz9vae5jtb7IHeIhTZgirHkr+g3uM+onP65x9abJTyUpURK1h0QCirc0PO
# 30qhHGs4xSnzyqqWc0Jon7ZGs506o9UD4L/wojzKQtwYSH8UNM/STKvvmz3+Drhk
# Kvp1KCRB7UK/BZxmSVJQ9FHzNklNiyDSLFc1eSuo80VgvCONWPfcYd6T/jnA+bIw
# pUzX6ZhKWD7TA4j+s4/TXkt2ElGTyYwMO1uKIqjBJgj5FBASA31fI7tk42PgpuE+
# 9sJ0sj8eCXbsq11GdeJgo1gJASgADoRU7s7pXcheMBK9Rp6103a50g5rmQzSM7TN
# sQIDAQABo4IBXTCCAVkwEgYDVR0TAQH/BAgwBgEB/wIBADAdBgNVHQ4EFgQUuhbZ
# bU2FL3MpdpovdYxqII+eyG8wHwYDVR0jBBgwFoAU7NfjgtJxXWRM3y5nP+e6mK4c
# D08wDgYDVR0PAQH/BAQDAgGGMBMGA1UdJQQMMAoGCCsGAQUFBwMIMHcGCCsGAQUF
# BwEBBGswaTAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29tMEEG
# CCsGAQUFBzAChjVodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRU
# cnVzdGVkUm9vdEc0LmNydDBDBgNVHR8EPDA6MDigNqA0hjJodHRwOi8vY3JsMy5k
# aWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkUm9vdEc0LmNybDAgBgNVHSAEGTAX
# MAgGBmeBDAEEAjALBglghkgBhv1sBwEwDQYJKoZIhvcNAQELBQADggIBAH1ZjsCT
# tm+YqUQiAX5m1tghQuGwGC4QTRPPMFPOvxj7x1Bd4ksp+3CKDaopafxpwc8dB+k+
# YMjYC+VcW9dth/qEICU0MWfNthKWb8RQTGIdDAiCqBa9qVbPFXONASIlzpVpP0d3
# +3J0FNf/q0+KLHqrhc1DX+1gtqpPkWaeLJ7giqzl/Yy8ZCaHbJK9nXzQcAp876i8
# dU+6WvepELJd6f8oVInw1YpxdmXazPByoyP6wCeCRK6ZJxurJB4mwbfeKuv2nrF5
# mYGjVoarCkXJ38SNoOeY+/umnXKvxMfBwWpx2cYTgAnEtp/Nh4cku0+jSbl3ZpHx
# cpzpSwJSpzd+k1OsOx0ISQ+UzTl63f8lY5knLD0/a6fxZsNBzU+2QJshIUDQtxMk
# zdwdeDrknq3lNHGS1yZr5Dhzq6YBT70/O3itTK37xJV77QpfMzmHQXh6OOmc4d0j
# /R0o08f56PGYX/sr2H7yRp11LB4nLCbbbxV7HhmLNriT1ObyF5lZynDwN7+YAN8g
# Fk8n+2BnFqFmut1VwDophrCYoCvtlUG3OtUVmDG0YgkPCr2B2RP+v6TR81fZvAT6
# gt4y3wSJ8ADNXcL50CN/AAvkdgIm2fBldkKmKYcJRyvmfxqkhQ/8mJb2VVQrH4D6
# wPIOK+XW+6kvRBVK5xMOHds3OBqhK/bt1nz8MIIGwjCCBKqgAwIBAgIQBUSv85Sd
# CDmmv9s/X+VhFjANBgkqhkiG9w0BAQsFADBjMQswCQYDVQQGEwJVUzEXMBUGA1UE
# ChMORGlnaUNlcnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQg
# UlNBNDA5NiBTSEEyNTYgVGltZVN0YW1waW5nIENBMB4XDTIzMDcxNDAwMDAwMFoX
# DTM0MTAxMzIzNTk1OVowSDELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0
# LCBJbmMuMSAwHgYDVQQDExdEaWdpQ2VydCBUaW1lc3RhbXAgMjAyMzCCAiIwDQYJ
# KoZIhvcNAQEBBQADggIPADCCAgoCggIBAKNTRYcdg45brD5UsyPgz5/X5dLnXaEO
# CdwvSKOXejsqnGfcYhVYwamTEafNqrJq3RApih5iY2nTWJw1cb86l+uUUI8cIOrH
# mjsvlmbjaedp/lvD1isgHMGXlLSlUIHyz8sHpjBoyoNC2vx/CSSUpIIa2mq62DvK
# Xd4ZGIX7ReoNYWyd/nFexAaaPPDFLnkPG2ZS48jWPl/aQ9OE9dDH9kgtXkV1lnX+
# 3RChG4PBuOZSlbVH13gpOWvgeFmX40QrStWVzu8IF+qCZE3/I+PKhu60pCFkcOvV
# 5aDaY7Mu6QXuqvYk9R28mxyyt1/f8O52fTGZZUdVnUokL6wrl76f5P17cz4y7lI0
# +9S769SgLDSb495uZBkHNwGRDxy1Uc2qTGaDiGhiu7xBG3gZbeTZD+BYQfvYsSzh
# Ua+0rRUGFOpiCBPTaR58ZE2dD9/O0V6MqqtQFcmzyrzXxDtoRKOlO0L9c33u3Qr/
# eTQQfqZcClhMAD6FaXXHg2TWdc2PEnZWpST618RrIbroHzSYLzrqawGw9/sqhux7
# UjipmAmhcbJsca8+uG+W1eEQE/5hRwqM/vC2x9XH3mwk8L9CgsqgcT2ckpMEtGlw
# Jw1Pt7U20clfCKRwo+wK8REuZODLIivK8SgTIUlRfgZm0zu++uuRONhRB8qUt+JQ
# ofM604qDy0B7AgMBAAGjggGLMIIBhzAOBgNVHQ8BAf8EBAMCB4AwDAYDVR0TAQH/
# BAIwADAWBgNVHSUBAf8EDDAKBggrBgEFBQcDCDAgBgNVHSAEGTAXMAgGBmeBDAEE
# AjALBglghkgBhv1sBwEwHwYDVR0jBBgwFoAUuhbZbU2FL3MpdpovdYxqII+eyG8w
# HQYDVR0OBBYEFKW27xPn783QZKHVVqllMaPe1eNJMFoGA1UdHwRTMFEwT6BNoEuG
# SWh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRHNFJTQTQw
# OTZTSEEyNTZUaW1lU3RhbXBpbmdDQS5jcmwwgZAGCCsGAQUFBwEBBIGDMIGAMCQG
# CCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wWAYIKwYBBQUHMAKG
# TGh0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRHNFJT
# QTQwOTZTSEEyNTZUaW1lU3RhbXBpbmdDQS5jcnQwDQYJKoZIhvcNAQELBQADggIB
# AIEa1t6gqbWYF7xwjU+KPGic2CX/yyzkzepdIpLsjCICqbjPgKjZ5+PF7SaCinEv
# GN1Ott5s1+FgnCvt7T1IjrhrunxdvcJhN2hJd6PrkKoS1yeF844ektrCQDifXcig
# LiV4JZ0qBXqEKZi2V3mP2yZWK7Dzp703DNiYdk9WuVLCtp04qYHnbUFcjGnRuSvE
# xnvPnPp44pMadqJpddNQ5EQSviANnqlE0PjlSXcIWiHFtM+YlRpUurm8wWkZus8W
# 8oM3NG6wQSbd3lqXTzON1I13fXVFoaVYJmoDRd7ZULVQjK9WvUzF4UbFKNOt50MA
# cN7MmJ4ZiQPq1JE3701S88lgIcRWR+3aEUuMMsOI5ljitts++V+wQtaP4xeR0arA
# VeOGv6wnLEHQmjNKqDbUuXKWfpd5OEhfysLcPTLfddY2Z1qJ+Panx+VPNTwAvb6c
# Kmx5AdzaROY63jg7B145WPR8czFVoIARyxQMfq68/qTreWWqaNYiyjvrmoI1VygW
# y2nyMpqy0tg6uLFGhmu6F/3Ed2wVbK6rr3M66ElGt9V/zLY4wNjsHPW2obhDLN9O
# TH0eaHDAdwrUAuBcYLso/zjlUlrWrBciI0707NMX+1Br/wd3H3GXREHJuEbTbDJ8
# WC9nR2XlG3O2mflrLAZG70Ee8PBf4NvZrZCARK+AEEGKMYIGPjCCBjoCAQEwaDBU
# MQswCQYDVQQGEwJHQjEYMBYGA1UEChMPU2VjdGlnbyBMaW1pdGVkMSswKQYDVQQD
# EyJTZWN0aWdvIFB1YmxpYyBDb2RlIFNpZ25pbmcgQ0EgUjM2AhANIM3qwHRbWKHw
# +Zq6JhzlMA0GCWCGSAFlAwQCAQUAoIGEMBgGCisGAQQBgjcCAQwxCjAIoAKAAKEC
# gAAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwG
# CisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIE8C6os6Aat90ElHNcpZsn5e0/wJ
# oSoCh8RzgHluX0eVMA0GCSqGSIb3DQEBAQUABIICAD6PMcgjXGGpX9JfmGmnm6UG
# 49fHMWCFyBctEUbUj5zXxvsrp0DOUhvrAkJ51hp1xH+qso8px1r8B+/yvQtyMCr/
# hx3z3jKOg3sgsN8rTwzuKZXd4qLfyy+39LzWvZQjguNCz9DO3duUN4nbpqf08KPj
# XgkkYkjXzdw2Kuy91U9HBIRi0+riFOcGw+uHc4vcY2KyZx5FvRf59XUqA73nfCuO
# uiVtnl1VUu2G1hx9Kkzqij+S4Cj5V+zi7zOHIn7fyiXQTQQ/C3qN5nNqRI60Wt1w
# OABsFKRChqnfHlNFi0QqG1YmIDbrSXhjxO4tauJFVaHB2tysorEZYwsu4yVNV5KR
# WJ/835ow8etQZXeO7yEuK0D4sL5XKYbbz9bfAcmFlllkDBx3Du3W7Xj+LgekKJLa
# YhWXptWIk0imcFL3qotbGM4wiEJYvdhgwjseBeNZaUQC0QL4w4A/WRhY5uSzB06x
# yd6Bq0UtHtwa2GNVWQTs3SvPpFTtA1w3J1dGE82Wvq3JJy1QsdnQhNfLQ9iyYcbE
# 9NQpeOWlb6D1kmnwhb0bT4tpWbhomfNCkqQ0bL9tpYNKmcaX97Jk42hC9MkXfXA/
# IeLFd2HlTSweLw9ny4KYxlIZF3dBuvPioibXTTYQq3Tsh11rtPnXZrR2o+wJSnNz
# sB0Q8AXUlSKi5iQUIhW3oYIDIDCCAxwGCSqGSIb3DQEJBjGCAw0wggMJAgEBMHcw
# YzELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQD
# EzJEaWdpQ2VydCBUcnVzdGVkIEc0IFJTQTQwOTYgU0hBMjU2IFRpbWVTdGFtcGlu
# ZyBDQQIQBUSv85SdCDmmv9s/X+VhFjANBglghkgBZQMEAgEFAKBpMBgGCSqGSIb3
# DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTI0MDQwNDE5NTk0MFow
# LwYJKoZIhvcNAQkEMSIEIBt+7VaC4gmnD+i1rcC61iXNGqq8JJpaxcxdDzo1BcCT
# MA0GCSqGSIb3DQEBAQUABIICAJ55MSoTmtI8YH+x5Lm01WKR0fFIrkJaSPLKtYvD
# ROm9S9wxP+7xOB6PbOsYWpqOgsjOjWDKQXKDO/lcxLohmhK2l2z1tPdUBGf9Ey2O
# ZVaFvuLT96OfxlVdv0VgtIsFuAi2JXZBj/8CM9/mdfOceMF669DU1YTZbimEfs/3
# NYpPbFkyP7LZ+pBBkZdOv6SV8skb54bAhPe9kzr8ELsPa4zB35eFPHO27SkTwIzi
# 5aygxfP6xdwxLV+3viGvJGvyycuiIz4hthakRxdoTM0ZLdEH3phLvjatoXIfrEMY
# i0BU0vX2JWT6fmDib70QZI+kE55/NEQp5RG78k/BwxJh2K4MhKODpq5MHyrzJthj
# lsnOzTXzbAQSc3ZesBKeq5qOq+BaWfG6R2kFdQsPdBzQd9dY6PNYiqTBUsaXbW3u
# lEeuOzJ5F8E2FzRUwF66hltZL3AE+EIBcxRIHO26J2HAOU+rn/VEVqXeYEENxEmB
# onk2nL9Rvwrb2Jz/fl0RTmwUng1Eqz1NvjFw6JtvgqpjefkTZWMHMsDQ74T8NzLZ
# YvqJ7z+LTp8016mFMr4YzeXykmZeA3jSau+jBojHgURnh82Scaysp+qHkQkpMyEe
# fwG7SJA5ziWvYUHOVNsWTisQCEP8WqmQeaUAWp9bux1Iq02UAVcjen9YOEZ/gBqQ
# P7Sa
# SIG # End signature block
