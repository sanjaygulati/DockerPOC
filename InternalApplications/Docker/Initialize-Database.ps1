param(
    [Parameter(Mandatory=$true)]
    [string] $sa_password,

    [Parameter(Mandatory=$true)]
    [string] $data_path)

# start the service
Write-Verbose 'Starting SQL Server'
Start-Service MSSQL`$SQLEXPRESS

if ($sa_password -ne "_") {
	Write-Verbose 'Changing SA login credentials'
    $sqlcmd = "ALTER LOGIN sa with password='$sa_password'; ALTER LOGIN sa ENABLE;"
    Invoke-SqlCmd -Query $sqlcmd -ServerInstance ".\SQLEXPRESS" 
}

$mdfPath = "$data_path\WebContent.mdf"
$ldfPath = "$data_path\WebContent_log.ldf"

# attach data files if they exist: 
if ((Test-Path $mdfPath) -eq $true) {
    $sqlcmd = "IF DB_ID('WebContent') IS NULL BEGIN CREATE DATABASE WebContent ON (FILENAME = N'$mdfPath')"
    if ((Test-Path $ldfPath) -eq $true) {
        $sqlcmd =  "$sqlcmd, (FILENAME = N'$ldfPath')"
    }
    $sqlcmd = "$sqlcmd FOR ATTACH; END"
    Write-Verbose 'Data files exist - will attach and upgrade database'
    Invoke-Sqlcmd -Query $sqlcmd -ServerInstance ".\SQLEXPRESS"
}
else {
     Write-Verbose 'No data files - will create new database'
}

# deploy or upgrade the database:
$SqlPackagePath = 'C:\Program Files (x86)\Microsoft SQL Server\130\DAC\bin\SqlPackage.exe'
& $SqlPackagePath  `
    /sf:FrameworkDB.dacpac `
    /a:Script /op:Frameworkdeploy.sql /p:CommentOutSetVarDeclarations=true `
    /tsn:.\SQLEXPRESS /tdn:WebContent /tu:sa /tp:$sa_password 

Write-Verbose $SqlPackagePath

$SqlCmdVars = "DatabaseName=WebContent", "DefaultFilePrefix=WebContent", "DefaultDataPath=$data_path\", "DefaultLogPath=$data_path\"  
Invoke-Sqlcmd -InputFile Frameworkdeploy.sql -Variable $SqlCmdVars -Verbose -ErrorAction Stop



# deploy or upgrade the database:
$SqlPackagePath = 'C:\Program Files (x86)\Microsoft SQL Server\130\DAC\bin\SqlPackage.exe'
& $SqlPackagePath  `
    /sf:WebContentDB.dacpac `
    /a:Script /op:deploy.sql /p:CommentOutSetVarDeclarations=true `
    /tsn:.\SQLEXPRESS /tdn:WebContent /tu:sa /tp:$sa_password 

Write-Verbose $SqlPackagePath

$WarningPreference = "Continue"
$VerbosePreference = "Continue"

$SqlCmdVars = "DatabaseName=WebContent", "DefaultFilePrefix=WebContent", "DefaultDataPath=$data_path\", "DefaultLogPath=$data_path\"  
Invoke-Sqlcmd -InputFile deploy.sql -Variable $SqlCmdVars -Verbose -outputsqlerrors $true

Write-Verbose "Deployed WebContent database, data files at: $data_path"

Write-Verbose "Applying TypeData"

# Apply type data.
Get-ChildItem c:\trunk\TypeData -recurse -include "*.xml" | `
 Foreach-Object{ `
    $xml = "'" +  "<Tables>" + (Get-Content $_) + "</Tables>" + "'"; `
    Invoke-SqlCmd -Query "Exec deployment.spcSourceControlLoadData $xml" -ServerInstance ".\SQLEXPRESS" -database "WebContent" -Verbose ; `
 }

Write-Verbose 'DONE WITH POWERSHELL'
