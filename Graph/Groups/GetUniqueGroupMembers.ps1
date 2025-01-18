# Define the Group IDs
$Group1Id = "<group1-id>"
$Group2Id = "<group2-id>"

# Get members of each group
$Group1Members = Get-MgGroupMember -GroupId $Group1Id -All -Property Id | Select-Object -ExpandProperty Id
$Group2Members = Get-MgGroupMember -GroupId $Group2Id -All -Property Id | Select-Object -ExpandProperty Id

# Find members unique to each group
$UniqueToGroup1 = $Group1Members | Where-Object { $_ -notin $Group2Members }
$UniqueToGroup2 = $Group2Members | Where-Object { $_ -notin $Group1Members }

# Output based on user choice
if ($UniqueToGroup1) {
        Write-Output "Members unique to Group 1:"
        $UniqueToGroup1 | ForEach-Object { Write-Output $_ }
    } else {
        Write-Output "No members are unique to Group 1."
    }
    Write-Output ""
    if ($UniqueToGroup2) {
        Write-Output "Members unique to Group 2:"
        $UniqueToGroup2 | ForEach-Object { Write-Output $_ }
    } else {
        Write-Output "No members are unique to Group 2."
    }
