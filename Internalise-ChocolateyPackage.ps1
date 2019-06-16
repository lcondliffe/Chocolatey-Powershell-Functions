<#
.Synopsis
   LW - ORC Endpoint Development
.DESCRIPTION
   Downloads a Chocolatey community package and pushes to an internal repository server.
.EXAMPLE
   Internalise-ChocolateyPackage -CommunityPackage 7zip -Recompile -Verbose
.EXAMPLE
   $packages = @("wireshark","winPcap")
   $packages | % {Internalise-ChocolateyPackage -CommunityPackage $_ -ChocolateyServerURL https://chocolatey.derby.ac.u/chocolatey -uod_api "KEYGOESHERE" -Verbose}
   Internalise-ChocolateyPackage -CommunityPackage jre8 -PackageVersion 8.0.191 -ChocolateyServerURL https://chocolatey-tst.derby.ac.uk/chocolatey -DownloadDirectory c:\temp -uod_api "thekeygoeshere" -Verbose
#>


#####

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