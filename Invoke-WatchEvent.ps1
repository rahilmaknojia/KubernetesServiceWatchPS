<#
    FileName: Invoke-WatchEvent.ps1
    Description: Purpose of this script is to watch kubernetes services and upon new events got triggered for type nodeport, perform action to create external load balancer.
    Created On: 02/11/2018
    Created By: Rahil Maknojia
#>

#regions Variables
$api_url = "http://127.0.0.1:8001/api/v1"
$services_url = $api_url + "/services"
$watch_services_url = $api_url + "/watch/services"
$nodes_url = $api_url + "/nodes"
$worker_nodes = $null
$master_nodes = "k8s-master-node" # Add master node names here with comma seperated values
$get_current_services_metadata = $null # Get metadata from services to ignore data received on first execution.
$get_current_service_names_metadata = $null # Get service names
$service_type = "nodeport" # Service type to filter on.
$ignore_namespaces = "kube-system" # Add comma seperated values that you would like to ignore.
$ignore_services = "kubernetes" # Add service names to ignore with comma seperated values.
#endregions

#regions Functions
function Create-LoadBalancer
{
    Param
    (
        [psobject]$object
    )

    return $object | ConvertTo-Json
}

function Delete-LoadBalancer
{
    Param
    (
        [psobject]$object
    )

    return $object | ConvertTo-Json    
}

function Get-WorkerNodes
{
    $data = Invoke-RestMethod -Method Get -Uri $nodes_url
    $node_data = $data.items | where {$_.metadata.name -notin $master_nodes}
    return $node_data
}

function Get-Services-Metadata
{
    $data = Invoke-RestMethod -Method Get -Uri $services_url
    return $data
}

function Create-LB-Metadata
{
    Param
    (
        [psobject]$object
    )

    $metadata = New-Object psobject
        $metadata | Add-Member -type NoteProperty -Name Name -Value $($object.object.metadata.name + "_lb_" + $object.object.metadata.namespace)
        $metadata | Add-Member -type NoteProperty -Name Node_ports -Value $object.object.spec.ports
        $metadata | Add-Member -type NoteProperty -Name Node_IPS -Value $worker_nodes.status.addresses

    return $metadata
}

function Remove-Old-Events
{
    Param
    (
        [psobject]$object
    )
    $data = $object
    # Filter and remove system namespaces
    $data = $data | where {$_.object.metadata.namespace -notin $ignore_namespaces -and $_.object.metadata.name -ne $ignore_services}
    # Filter service type nodeport
    $data = $data | where {$_.object.spec.type -eq "nodeport"}
    # Filter and remove previous events
    $data = $data | where {$_.object.metadata.name -notin $get_current_service_names_metadata}

    return $data
}

function Process-Request
{
    Param
    (
        [psobject]$object
    )
    $data = $object
    $data = Remove-Old-Events -object $data
    if ($data.type -eq "ADDED")
    {
        # Create Load balancer
        $metadata = Create-LB-Metadata -object $data
        Create-LoadBalancer -object $metadata
    }
    if ($data.type -eq "DELETED")
    {
        # Delete Load balancer
        # Add logic here

    }
    if ($data.type -eq "MODIFIED")
    {
        # Modify Load balancer 
        # Add logic here

    }
}

#endregions

#regions Default Metadata
$get_current_services_metadata = Get-Services-Metadata
$get_current_service_names_metadata = ($get_current_services_metadata.items | Where-Object {$_.metadata.name -notin $ignore_services -and $_.metadata.namespace -notin $ignore_namespaces}).metadata.name
$worker_nodes = Get-WorkerNodes
#endregions

#regions HTTP Watch Request
$request = [System.Net.WebRequest]::Create($watch_services_url)
# Get Response
$resp = $request.GetResponse()
# Get Response Stream
$reqstream = $resp.GetResponseStream()
# Create new object for StreamReader
$sr = New-Object System.IO.StreamReader $reqstream
# Create a loop for listening for new events
while (!$sr.EndOfStream)
{
    # Read the line
    $line = $sr.ReadLine();
    # Convert json string to PSObject
    $line_object = $line | ConvertFrom-Json
    # Get Metadata
    $metadata = $line_object.object.metadata
    # Get request type
    $type = $line_object.type

    # Process data returned
    Process-Request -object $line_object
}

#endregions