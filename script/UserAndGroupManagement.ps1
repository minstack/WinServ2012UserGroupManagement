## Using the provided CSV file (path), creates
## creates bulk user.  The csv columns must be in the format
## Username,UPN,GivenName,Surname,DisplayName,Path,Password,Group
function Create-UsersFromCSV {
    param([string]$UserCSVPath)

    $userCount = 0

    Import-Csv $UserCSVPath |
    
    ForEach {
        New-ADUser $_.Username `
        -UserPrincipalName $_.UPN `
        -GivenName $_.GivenName `
        -Surname $_.Surname `
        -DisplayName $_.DisplayName `
        -Path $_.Path `
        -AccountPassword (ConvertTo-SecureString -AsPlainText $_.Password -Force) `
        -ChangePasswordAtLogon $true `
        -Enabled $true

        $userCount++

        Write-Host "-Creating user $($_.Username)..." -ForegroundColor DarkGreen
    }

    Write-Host "$userCount users created" -ForegroundColor Yellow
}

## Creates Organizational Units based on the give CSV file
## Name,Path
## Path is the normal AD path structure:
## "DC=domain,DC=.ext"
## Child OUs: "OU=grandparent, ou=parent, DC=domain, DC=.ext"
## Of course the parent OUs must be created first -> top down in the csv file
function Create-BulkOUcsv {
    param([string]$OUcsvPath)

    $ouCount = 0

    Import-Csv $OUcsvPath |
    ForEach {
        New-ADOrganizationalUnit $_.Name `
        -Path $_.Path    

        $ouCount++

        Write-Host "-Creating OU $($_.Name)" -ForegroundColor DarkGreen
    }

    Write-Host "$ouCount OUs created" -ForegroundColor Yellow
}


## Creates Security Groups based on the records of the given CSV file.
## ParentGroup is optional but if provided child groups will be automatically added
## The parent group must be created first -> at the top of the CSV file.
## Must be in the column format of Name,GroupScope,Path,ParentGroup
function Create-BulkSecGroupsCsv {
    param([string]$SecGroupCsvPath)

    $secGcount = 0

    Import-Csv $SecGroupCsvPath |
    ForEach {
        $parentGroup = $_.ParentGroup

        New-ADGroup `
        -Name $_.Name `
        -GroupScope $_.GroupScope `
        -Path $_.Path

        $secGcount++

        Write-Host "-Creating Security Group $($_.Name)" -ForegroundColor DarkGreen

        if ($parentGroup) {
            Add-ADGroupMember $parentGroup $_.Name        
        }
    }

    Write-Host "$secGcount security groups created" -ForegroundColor Yellow
}

## Creates bulk folders from the provided CSV.
## Single column list:
## Path
## fullPathofDirectory
## this will create all parent directories if they do not exist
function Create-FoldersCsv {
    param([string]$FolderCsvPath)

    Import-Csv $FolderCsvPath |
    ForEach {
        
        $fullPath = $_.Path

        New-Item -Type directory -path $fullPath -Force | Out-Null

        Write-Host "-Created full path of folders: $fullPath" -ForegroundColor DarkGreen
    }
}

## Adds users in the provided CSV file to the specified groups
## Column format (within the users csv):
## Username,UPN,GivenName,Surname,DisplayName,Path,Password,Group
function Add-BulkUserToGroup {
    param([string]$UserCsvPath)
    
    Import-Csv $UserCsvPath | 
    ForEach {
        $group = $_.Group

        if ($group) {
            $secGroup = "sec" + $group

            Add-ADGroupMember $secGroup $_.Username

            Write-Host "-Adding $($_.Username) to Group $secGroup" -ForegroundColor DarkGreen
        }
        
    }
}

## The main function to run the automation of creating OUs, SecGroups,
## Users and folders.  The CSV file here is the collection of all the
## necessary CSV file paths for OUs, Users, Groups etc for bulk creation.
## Omitting the field entry in the CSV file will skip that process.
## Must be in the column format:  
## OUCSV,SecCSV,UsersCSV,Folders,Sharescsv
## ".\csv\ous.csv",,".\csv\users.csv",,
## the above entry will only create given OUs and Users
function Run-OUSecGroupUserAuto {
    param([string]$csvFilesLoc, [string]$SharePath, [string]$ShareName, [string]$ShareParentGroup)

    Import-Csv $csvFilesLoc |

    ForEach {
        $oucsv = $_.OUCSV
        $secsv = $_.SecCSV
        $userscsv = $_.UsersCSV
        $foldercsv = $_.Folders
        $gpocsv = $_.GPOcsv

        if($oucsv){
            Write-Host "`n**************    Creating Bulk OUs from $oucsv..." -ForegroundColor Green
            Create-BulkOUcsv -OUcsvPath $oucsv
        }
        
        if ($secsv){
            Write-Host "`n**************    Creating Bulk SecGroups from $secsv..." -ForegroundColor Green
            Create-BulkSecGroupsCsv -SecGroupCsvPath $secsv
        }
        
        if ($userscsv) {
            Write-Host "`n**************    Creating Bulk Users from $userscsv..." -ForegroundColor Green
            Create-UsersFromCSV -UserCSVPath $userscsv
            Write-Host "**************    Adding Bulk Users to Groups..." -ForegroundColor Green
            Add-BulkUserToGroup -UserCsvPath $userscsv
        }
        
        if ($foldercsv){
            Write-Host "`n**************    Creating Folders from $foldercsv..." -ForegroundColor Green
            Create-FoldersCsv -FolderCsvPath $foldercsv
        }

        if ($SharePath -and $ShareName) {
            Write-Host "`n**************    Setting Folder Permissions for Shares..." -ForegroundColor Green
            Create-ShareWithPermissions -ShareInfoCsv $_.Sharescsv -SharePath $SharePath -ShareName $ShareName -ParentShareGroup $ShareParentGroup
            Remove-BuiltinUserAcl -Path $SharePath
        }

        if ($gpocsv) {
            Import-Module servermanager

            if (!(Get-WindowsFeature gpmc).installed) {
                Write-Host "`n**************    INSTALLING GROUP POLICY MANAGEMENT CONSOLE..." -ForegroundColor Cyan
                Add-WindowsFeature gpmc            
            }
            Write-Host "`n**************    Creating GPOs from $gpocsv..." -ForegroundColor Green

            Create-GPOBulkCsv -CsvPath $gpocsv
        }
       
    }

}

## Creates GPOs and places a GPO link to the provided target ou
## If the target OU is not provided in the CSV file, only the GPO will be created.
function Create-GPOBulkCsv {
    param($CsvPath)

    Import-Csv $CsvPath | 
    foreach {
        $gpoName = $_.GPOName
        $target = $_.TargetOUPath
        
        Write-Host "-Creating GPO $gpoName..." -ForegroundColor DarkGreen
        $GPO = New-GPO -Name $gpoName

        if ($target) {
            Write-Host "--Linking $gpoName to $target..." -ForegroundColor DarkCyan
            $GPO | New-GPLink -Target $target | Out-Null 
        }
        
    }


}


## Creates a share with the provided share name and share path.
## if the CSV for subfolders within the share is provided, this
## configures the permissions of the subfolders of the share based
## on the CSV file.
## CSV column format:
## SubShareFolder,Group,Permission,Flag
## subFolderName,"domain\userORgroup", "Read/Modify/[many more]", "Allow/Deny"
function Create-ShareWithPermissions {
    param([string]$ShareInfoCsv, [string]$SharePath, [string]$ShareName, [string]$ParentShareGroup)

    ## allowing everyone full accesss to the share -> visible
    ## restricts the actual access/modifying with removing builtin users and
    ## individual NTFS permission on each subfolder
    New-SmbShare -Name $ShareName -Path $SharePath -FullAccess everyone | Out-Null
    Remove-BuiltinUserAcl -Path $SharePath

    ## allows for the parent group to access this folder
    ## but cannot modify the folder itself
    ## allows to see the subfolders which will have their own
    ## permission for modifying per group
    if ($ParentShareGroup) {
        Set-FolderPermission `
            -Path $SharePath `
            -User $ParentShareGroup `
            -Permission "ReadAndExecute" `
            -Inherit "None" `
            -Propagation "None" `
            -ACLType "Allow"       
    }
   

    if ($ShareInfoCsv) {
        Import-Csv $ShareInfoCsv |
        ForEach {
            $subShareDir = $SharePath + "\" + $_.SubShareFolder
            $inherit = "ContainerInherit, ObjectInherit" 
            $prop = "None"
            $acltype = "Allow"

            Remove-BuiltinUserAcl -Path $subShareDir

            Set-FolderPermission -Path $subShareDir -User $_.Group -Permission $_.Permission -Inherit $inherit -Propagation $prop -ACLType $acltype
                    
            Write-Host "-Setting $($_.Group) Modify permission for $subShareDir" -ForegroundColor Yellow
   
        }    
    }
}

## Removes the inherited BUILTIN/users from a given directory path
function Remove-BuiltinUserAcl {
    param($Path)
   
    Remove-Permissions -Path $Path -IsProtected $true -PreserveInherit $true -IdentityRef "BUILTIN\Users"
}

## Removes the (NTFS) permission for the provided path with settings of is protected (bool),
## preserving inheritance (bool) and the group/user identity reference to remove
## 
## thanks to Luben Kirov
## http://www.gi-architects.co.uk/2017/01/the-acl-removeaccessrule-not-working/
## slightly modified from the above to be more modular
function Remove-Permissions {
    param($Path, [bool]$IsProtected, [bool]$PreserveInherit, [string]$IdentityRef)

    $acl = Get-Acl $Path
    $acl.SetAccessRuleProtection($IsProtected,$PreserveInherit) #protected, preserve inheritance
    Set-Acl $Path $acl

    # must get the acl again since above changed
    $acl = Get-Acl $Path
    $acl.Access | Where-Object {$_.IdentityReference -eq $IdentityRef} | ForEach-Object { $acl.RemoveAccessRule($_)} | Out-Null

    Set-Acl $Path $acl

}


## Setting NTFS permissions of the provided directory with the given user/group,
## permissions, inherit, propagation and acl type.
##
## thanks to Jose Barreto
## https://blogs.technet.microsoft.com/josebda/2010/11/12/how-to-handle-ntfs-folder-permissions-security-descriptors-and-acls-in-powershell/
function Set-FolderPermission {
    param([string]$Path, [string]$User, [string]$Permission, $Inherit, $Propagation,$ACLType)
    
    $dirAcl = Get-Acl $Path
    $dirRule = New-Object System.Security.AccessControl.FileSystemAccessRule($User, $Permission, $Inherit, $Propagation, $ACLType)
    $dirAcl.AddAccessRule($dirRule)

    Set-Acl $Path $dirAcl

}

$cVars=@{}

## init dictionary with variables for user/group creation
## left hand side of the config.txt must be kept as-is for
## this script to work
Import-Csv c:\scripts\config.txt | 

ForEach {
    [string]$confLine=$_.ConfigVars

    $key,$val = $confLine.Split('=')

    $cVars.Add($key,$val)
}

$sharePath = $cVars['SharePath']
$shareName = $cVars['ShareName']
$parentGroupShare = $cVars['ShareGroupAccess']

Run-OUSecGroupUserAuto `
    -csvFilesLoc .\csv\autocreate.csv `
    -SharePath $sharePath `
    -ShareName $shareName `
    -ShareParentGroup $parentGroupShare
