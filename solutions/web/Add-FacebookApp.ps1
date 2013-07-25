param(
    [Parameter(Mandatory = $true)]
    [String]$WebSiteName,

    [Parameter(Mandatory = $true)]
    [String]$WebSiteLocation,

    [Parameter(Mandatory = $true)]
    [String]$SQLDatabaseUsername,

    [Parameter(Mandatory = $true)]
    [String]$SQLDatabasePassword,

    [Parameter(Mandatory = $true)]
    [String]$WebSiteProjectFilePath,

    [Parameter(Mandatory = $true)]
    [String]$FacebookAppId,

    [Parameter(Mandatory = $true)]
    [String]$FacebookSecretKey
)

$powershellSamplesRoot = "D:\Projects\3d party\azure-powershell-samples"

& $powershellSamplesRoot\create-azure-website-env.ps1 -Name $WebSiteName -Location $WebSiteLocation `
-SqlDatabaseUserName $SQLDatabaseUsername -SqlDatabasePassword $SQLDatabasePassword

& $powershellSamplesRoot\deploy-azure-website-devbox.ps1 -ProjectFile $WebSiteProjectFilePath

$settings = New-Object Hashtable
$settings["FacebookAppId"] = $FacebookAppId
$settings["FacebookAppSecret"] = $FacebookSecretKey

Get-AzureWebsite -Name $WebSiteName | Set-AzureWebsite -AppSettings $settings

