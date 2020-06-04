#LW 09/05/19
#Chocolatey Automated Package Internalisation Process

##Variable Declaration##
$repo = ""
$Community_repo = "https://chocolatey.org/api/v2/"
$chocolatey_api_key = "APIKEYHERE"
$download_dir = "C:\TEMP\"
#These packages will not be internalised automatically by the process:
$Exclusions = "wireshark", "unity", "androidstudio", "avecto-defendpoint-client", "avecto-defendpoint-console", "houdini"

##Function Declaration##

Function Internalise-ChocolateyPackage
{
    [CmdletBinding()]
    [Alias()]
    [OutputType([int])]
    Param
    (
        #Name of the Chocolatey community package.
        [Parameter(Mandatory= $true,
                   ValueFromPipeline = $true,
                   Position=0)]
        [string]$CommunityPackage,

        #Chocolatey Server Name
        $ChocolateyServerURL = "https://chocolatey.derby.ac.uk/chocolatey",

        #Optionally specify a download directory
        $DownloadDirectory,

        #Optionally specify a version of the community package
        $PackageVersion,

        #Optionally add the recompile switch to the Chocolatey download
        [switch]$Recompile,

        #University Internal Repository api-key
        $uod_api = "ADDTHEKEYHERE"
        )
    
    Begin
    {
        #Check Chocolatey version and edition
        $chocolatey_client = choco
        $chocolatey_client = $chocolatey_client[0]
        if ($chocolatey_client -like "*Business*"){
            Write-Verbose "Chocolatey is licensed correctly and is version $chocolatey_client"
        }
        else{
            Write-Warning "Chocolatey is not a licensed version on this machine, download and push attempts will fail."
            $process = $false
        }

        #Check download location if specified
        if($DownloadDirectory -ne $null){
            Write-Verbose "Checking download location: $DownloadDirectory"
            if((Test-Path $DownloadDirectory) -eq $true){
                Write-Verbose "$DownloadDirectory is a valid path."
            }
            else{
                Write-Warning "$DownloadDirectory is not a valid path. Make sure this folder exists and try again."
                $process = $false
            }
        }

        #Validate package
        Write-Verbose "Checking validity of $CommunityPackage on Chocolatey repositories."
        if ($PackageVersion -eq $null){
            $package = choco search $CommunityPackage -exact -limitoutput
        }
        else{
            $package = choco search $CommunityPackage --version $PackageVersion -exact -limitoutput
        }
        
        if ($package.count -eq 0){
            Write-Warning "$CommunityPackage $PackageVersion does not exist on available repositories."
            $process = $false
        }
        else{
            Write-Verbose "$package available on Chocolatey repositories."
        }

        #Validate Chocolatey server
            #Check chocolatey repository is available
            
            $repo_check = try {
                #By default powershell uses TLS 1.0 the site security requires TLS 1.2
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                Write-Verbose "Checking repository on $ChocolateyServerURL"
                $choco_site = Invoke-WebRequest $ChocolateyServerURL -UseBasicParsing
            } catch {
                Write-Warning "Unable to connect to the Chocolatey web server."
                $process = $false
            }

            if ($repo_check -eq $null){
                Write-Verbose "Successfully connected to Chocolatey repository on $ChocolateyServerURL"
            }
            else{
                Write-Warning "Failed to connect to Chocolatey repository on $ChocolateyServerURL with error $repo_check"
                $process = $false
            }
    }
    Process
    {
        $starting_directory = Get-Location

        if ($process -ne $false){
            Write-Verbose "Pre-Requisite checks passed."
            
            if($DownloadDirectory -eq $null){
                Write-Verbose "Content will be downloaded to current running directory."
            }
            else{
                Write-Verbose "Switching to specified download dir ($DownloadDirectory)"
                cd $DownloadDirectory
            }

            #Create a subfolder for the download
            $datetime = Get-Date -Format "dd.MM.yyyy HHmm"
            $subdir = "$CommunityPackage $datetime"

            Write-Verbose "Creating new sub-directory at $subdir"
            New-Item $subdir -ItemType directory -Force
            cd $subdir
            
            #Package Download
            if ($PackageVersion -eq $null){
                if ($Recompile -eq $false){
                    Write-Verbose "Downloading $CommunityPackage (latest)"
                    choco download $CommunityPackage --force
                }
                elseif($Recompile -eq $true){
                    Write-Verbose "Downloading $CommunityPackage (latest)"
                    Write-Verbose "Recompile ENABLED"
                    choco download $CommunityPackage --recompile --force
                }               
            }
            elseif($packageVersion -ne $null){
                if ($Recompile -eq $false){
                    Write-Verbose "Downloading $CommunityPackage version $PackageVersion"
                    choco download $CommunityPackage --version $PackageVersion --force
                }
                elseif($Recompile -eq $true){
                    Write-Verbose "Downloading $CommunityPackage (latest)"
                    Write-Verbose "Recompile ENABLED"
                    choco download $CommunityPackage --version $PackageVersion --recompile --force
                }   
            }

            #Gather downloaded files
            $package_files = ls *$CommunityPackage*.nupkg
            #Push packages to repository
            $package_files | % {
                Write-Verbose "Push $_ to $ChocolateyServerURL"
                choco push "$_" --source $ChocolateyServerURL --api-key $uod_api --force
            }
        }
    }
    End
    {
        #Return to original working dir (or specified one)
        Set-Location $starting_directory
        Write-Verbose "Exiting Function"
    }
}

Function Write-Log {
    [CmdletBinding()]
    Param(
    [Parameter(Mandatory=$True)]
    [string]
    $Message,
    [Parameter(Mandatory=$False)]
    [ValidateSet("INFO","WARN","ERROR","FATAL","DEBUG")]
    [String]
    $Level = "INFO",

    [Parameter(Mandatory=$False)]
    [string]
    $logfile = "c:\temp\sch_internalise.log"
    )

    $log_exist = Test-Path $logfile
    if ($log_exist -eq $false){
        New-Item $logfile -ItemType file -Force > $null
    }

    $Stamp = (Get-Date).toString("yyyy/MM/dd HH:mm:ss")
    $Line = "$Stamp $Level $Message"
    If($logfile) {
        Add-Content $logfile -Value $Line
        Write-Output $Line
    }
    Else {
        Write-Output $Line
    }
}

function Send-TeamsMessage
{
    [CmdletBinding()]
    [Alias()]
    [OutputType([int])]
    Param
    (
        #Teams Message Text
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true,
                   Position=0)]
        $message,

        [switch] $critical,
        [switch] $warning,
        [switch] $success
    )

    #Replace with web hook connector in any channel
    $uri = "https://outlook.office.com/webhook/219f56d3-a555-4727-803e-8a275fff5119@98f1bb3a-5efa-4782-88ba-bd897db60e62/IncomingWebhook/5d582b8718084c1baf49f2045d456ace/193b454a-76a2-4e08-8b62-3e2ba640298b"

if ($critical){
    $body = ConvertTo-JSON @{
        themeColor = 'c60919'
        text = $message
}
}
elseif ($warning){
    $body = ConvertTo-JSON @{
        themeColor = 'eaaf0e'
        text = $message
}
}
elseif ($success){
    $body = ConvertTo-JSON @{
        themeColor = '0eea3a'
        text = $message
}
}
else{
    $body = ConvertTo-JSON @{
        text = $message
    }
}

Invoke-RestMethod -uri $uri -Method Post -body $body -ContentType 'application/json'
}

##BEGIN##

#Get a list of all packages available on the internal repository.
$package_list = choco search --source=$repo --limitoutput
#Strip version details from each object, use array list object type to allow easier removing of items from the list for exclusions:
[System.Collections.ArrayList]$package_list = $package_list | % {$_.Substring(0, $_.lastIndexOf('|'))}

#Remove Exclusions from the package list var
$Exclusions | % {$package_list.Remove("$_")}

foreach ($package in $package_list) {
    
    #Compare versions on local and remote repositories
    Write-Log "Checking for new versions of $package"
    $choco_local_verison = choco search $package --source=$repo -exact -limitoutput
    $choco_community_version = choco search $package --source=$Community_repo -exact -limitoutput

    if ($choco_community_version -eq $null){
        Write-Log "$package was not found on the community repository, this is likely to be an internally authored package or no longer available and will be skipped" -Level WARN
    }
    else{
        $check = compare-object -ReferenceObject $choco_local_verison -DifferenceObject $choco_community_version
        if ($check.count -ge 1){
            Write-Log "$package version outdated. $choco_local_verison is on-premise, $choco_community_version is available on the community repository. An attempt will be made to internalise this new version." -Level WARN

            #Call internalisation function:
            Internalise-ChocolateyPackage -CommunityPackage $package -ChocolateyServerURL $repo -DownloadDirectory $download_dir -uod_api $chocolatey_api_key -Verbose
            $updated_packages += " $package,"
        }
        else{
            Write-Log "$package version is up to date"
            }
    }
}
#If any new package versions have been internalised, notify.
if($updated_packages -ne $null){
    Write-Log "$updated_packages has been automatically internalised to $repo."
    Send-TeamsMessage -message "$updated_packages has been automatically internalised to $repo." -Success
}
