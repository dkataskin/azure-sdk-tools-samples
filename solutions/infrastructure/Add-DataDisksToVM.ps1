<#
.SYNOPSIS
  Creates a Virtual Machine with two data disks.
.DESCRIPTION
  Creates a Virtual Machine (small) configured with two data disks.  After the Virtual Machine is provisioned and running,
  the data disks are then formatted and have drive letters assigned.  User is prompted for credentials to use to provision
  the new Virtual Machine.

  If there is a VM with the given name, under the given cloud service, the script simply adds new disks to it and formats
  the new disks.

  Note: This script requires an Azure Storage Account to run.  Storage account can be specified by setting the 
  subscription configuration.  For example:
    Set-AzureSubscription -SubscriptionName "MySubscription" -CurrentStorageAccount "MyStorageAccount"

  Note: There are limits on the number of disks attached to VMs as dictated by their size. This example does not validate
  the disk number for the default VM size, which is small.  
.EXAMPLE
  Add-DataDisksToVM.ps1 -ServiceName "MyServiceName" -VMName "MyVM" -Location "West US" -NumberOfDisks 2 -DiskSizeInGB 16

#>

param(

    # Cloud service name to deploy the VMs to
    [Parameter(Mandatory = $true)]
    [String]$ServiceName,

    # Name of the Virtual Machine to create
    [Parameter(Mandatory = $true)]
    [String]$VMName,

    # Location, this is not a mandatory parameter. THe script checkes the existence if service is not found.
    [Parameter(Mandatory = $false)]
    [String]$Location,
        
    # Disk size in GB
    [Parameter(Mandatory = $true)]
    [Int32]$DiskSizeInGB,

    # Number of data disks to add to each virtual machine
    [Parameter(Mandatory = $true)]
    [Int32]$NumberOfDisks
)


<#
.SYNOPSIS
   Installs a WinRm certificate to the local store
.DESCRIPTION
   Gets the WinRM certificate from the Virtual Machine in the Service Name specified, and 
   installs it on the Current User's personal store.
.EXAMPLE
    Install-WinRmCertificate -ServiceName testservice -vmName testVm
.INPUTS
   None
.OUTPUTS
   Microsoft.WindowsAzure.Management.ServiceManagement.Model.OSImageContext
#>
function Install-WinRmCertificate($ServiceName, $VMName)
{
    $vm = Get-AzureVM -ServiceName $ServiceName -Name $VMName
    $winRmCertificateThumbprint = $vm.VM.DefaultWinRMCertificateThumbprint
 
    $winRmCertificate = Get-AzureCertificate -ServiceName $ServiceName -Thumbprint $winRmCertificateThumbprint -ThumbprintAlgorithm sha1

    $installedCert = Get-Item Cert:\CurrentUser\My\$winRmCertificateThumbprint -ErrorAction SilentlyContinue

    if ($installedCert -eq $null)
    {
        $certBytes = [System.Convert]::FromBase64String($winRmCertificate.Data)
        $x509Cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate
        $x509Cert.Import($certBytes)
 
        $store = New-Object System.Security.Cryptography.X509Certificates.X509Store "Root", "LocalMachine"
        $store.Open("ReadWrite")
        $store.Add($x509Cert)
        $store.Close()
    }
}

# Image name to create the Virtual Machine from.  Use Get-AzureVMImage for list of available images.
$imageName = "a699494373c04fc0bc8f2bb1389d6106__Windows-Server-2012-Datacenter-201306.01-en.us-127GB.vhd"

# Check if hosted service with $ServiceName exists
$existingService = Get-AzureService -ServiceName $ServiceName -ErrorAction SilentlyContinue

# Does the VM exist? If the VM is already there, just add the new disk
$existingVm = Get-AzureVM -ServiceName $ServiceName -Name $VMName -ErrorAction SilentlyContinue

if ($existingService -eq $null)
{
    if ($Location -eq "")
    {
        throw "Service does not exist, please specify the Location parameter"
    } 
    New-AzureService -ServiceName $ServiceName -Location $Location
}

if (($Location -ne "") -and ($existingService -ne $null))
{
    if ($existingService.Location -ne $Location)
    {
        Write-Warning "There is a service with the same name on a different location. Location parameter will be ignored."
    }
}


# Get credentials from user to use to configure the new Virtual Machine
$credential = Get-Credential

# Configure the new Virtual Machine.
$userName = $credential.GetNetworkCredential().UserName
$password = $credential.GetNetworkCredential().Password

if ($existingVm -ne $null)
{
    # Find the starting LUN for the new disks
    $startingLun = ($existingVm | Get-AzureDataDisk | Measure-Object Lun -Maximum).Maximum + 1

    for ($index = $startingLun; $index -lt $NumberOfDisks + $startingLun; $index++)
    { 
        $diskLabel = "disk_" + $index
        $existingVm = $existingVm | 
                      Add-AzureDataDisk -CreateNew -DiskSizeInGB $DiskSizeInGB -DiskLabel $diskLabel -LUN $index        
    }

    $existingVm | Update-AzureVM
}
else
{
    $vmConfig = New-AzureVMConfig -Name $VMName -InstanceSize Small -ImageName $imageName  |
                Add-AzureProvisioningConfig -Windows -AdminUsername $userName -Password $password 
                
    for ($index = 0; $index -lt $NumberOfDisks; $index++)
    { 
        $diskLabel = "disk_" + $index
        $vmConfig = $vmConfig | 
                    Add-AzureDataDisk -CreateNew -DiskSizeInGB $DiskSizeInGB -DiskLabel $diskLabel -LUN $index        
    }

    # Create the Virtual Machine and wait for it to boot.
    New-AzureVM -ServiceName $ServiceName -VMs $vmConfig -WaitForBoot
}

# Install a remote management certificate from the Virtual Machine.
Install-WinRmCertificate -serviceName $ServiceName -vmName $VMName

# Format data disks and assign drive letters.
$winRmUri = Get-AzureWinRMUri -ServiceName $ServiceName -Name $VMName
Invoke-Command -ConnectionUri $winRmUri.ToString() -Credential $credential -ScriptBlock {
    Get-Disk | 
    Where-Object PartitionStyle -eq "RAW" |
    Initialize-Disk -PartitionStyle MBR -PassThru |
    New-Partition -AssignDriveLetter -UseMaximumSize |
    Format-Volume -FileSystem NTFS -Confirm:$false
}