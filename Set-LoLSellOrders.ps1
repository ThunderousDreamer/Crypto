<#
    #Requires -Version 3.0
    .Synopsis
    Places sell half on a double orders through coinigy
    .DESCRIPTION
    Supply exchange, market name, amount bought, and price bought at. This script will 
    use your coinigy API key to place sell half on a double orders as many times as you want. 
    I'm not sure what the API limitations are.
    .EXAMPLE
    Set-LoLSellOrders -Exchange cryptopia -Market '1337/BTC' -Amount 1186000 -Price .00000004 -numOrders 10 -xApiKey $XAPIKEY -xApiSec $XAPISEC
    .NOTES
    20180311 TODO add stop limit orders and SuperJay's sell 25% x2x3
#>

function Set-LoLSellOrders
{
  [CmdletBinding()]
  [Alias("lol")]
  [OutputType([int])]
  Param
  (
    #Exchange shortname on coinigy
    [Parameter(Mandatory=$true,
    ValueFromPipelineByPropertyName=$true)]
    $Exchange,
            
    #Asset purchased
    [Parameter(Mandatory=$true,
    ValueFromPipelineByPropertyName=$true)]
    [string]
    $Market,

    #Amount purchased
    [Parameter(Mandatory=$true,
    ValueFromPipelineByPropertyName=$true)]
    [decimal]
    $Amount,
        
    #Price purchased@
    [Parameter(Mandatory=$true,
    ValueFromPipelineByPropertyName=$true)]
    [decimal]
    $Price,
    
    #Number of sell half on a double orders
    [Parameter(Mandatory=$true,
    ValueFromPipelineByPropertyName=$true)]
    [int]
    $numOrders,
    
    #Coinigy API Key
    [Parameter(Mandatory=$true,
    ValueFromPipelineByPropertyName=$true)]
    [string]
    $xApiKey, 
    
    #Coinigy API Secret
    [Parameter(Mandatory=$true,
    ValueFromPipelineByPropertyName=$true)]
    [string]
    $xApiSec
  )
  
  ####Functions
  function Get-ExchangeAuthID ($exchange,$xApiKey,$xApiSec) {
    $uri = "https://api.coinigy.com/api/v1/accounts"
    $hdrs = @{"X-API-KEY"=$xApiKey; "X-API-SECRET"=$xApiSec}
    $result = Invoke-RestMethod -Uri $URI -Method Post -Headers $hdrs
    $result.data | Where-Object {$_.exch_name -eq $exchange}
  }
  function get-exchange ($xApiKey,$xApiSec){
    $uri = "https://api.coinigy.com/api/v1/exchanges"
    $hdrs = @{"X-API-KEY"=$xApiKey; "X-API-SECRET"=$xApiSec}
    $result = Invoke-RestMethod -Uri $URI -Method Post -Headers $hdrs
    return $result.data
  }
  function Get-Market ($exch_code,$xApiKey,$xApiSec){
    $uri = "https://api.coinigy.com/api/v1/markets"
    $hdrs = @{"X-API-KEY"=$xApiKey; "X-API-SECRET"=$xApiSec}
    $body = @{"exchange_code"=$exch_code}
    $result = Invoke-RestMethod -Uri $URI -Method Post -Headers $hdrs -Body $body  
    $result.data
  }
  function New-DoublesTable
  {
    [CmdletBinding()]
    [Alias("double")]
    [OutputType([int])]
    Param
    (
      #Amount purchased
      [Parameter(Mandatory=$true,
      ValueFromPipelineByPropertyName=$true)]
      [decimal]
      $Amount,
              
      #Price bought @
      [Parameter(Mandatory=$true,
      ValueFromPipelineByPropertyName=$true)]
      [decimal]
      $Price,
      
      #Number of 1/2 doubles to create
      [Parameter(Mandatory=$true,
      ValueFromPipelineByPropertyName=$true)]
      [int]
      $numOrders
    )
    $doublesTable = @()
    for ($i=1; $i -le $numOrders; $i++){
      #sell orders
      $x = ([math]::pow(2,$i))
      $sellAt = $price*$x 
      #amount       
      $Amount = $Amount/2
      $prp =  New-Object psobject
      $prp | Add-Member NoteProperty SellAt $sellAt
      $prp | Add-Member NoteProperty Amount $Amount
      $doublesTable+=$prp
  
    }          
    $doublesTable
  }
  function Set-Order ($body,$xApiKey,$xApiSec) {
    $uri = "https://api.coinigy.com/api/v1/addOrder"
    $hdrs = @{"X-API-KEY"=$xApiKey; "X-API-SECRET"=$xApiSec}
    $result = Invoke-RestMethod -Uri $URI -Method Post -Headers $hdrs -Body $body  
    $result
  }
  
  ####Main
  #enables tls 1.2
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  
  #Create doubles table
  $doublesTable = New-DoublesTable -Amount $Amount -Price $Price -numOrders $numOrders
  
  #Get exchange info
  function Get-Exchange ($xApiKey,$xApiSec) {
    $uri = "https://api.coinigy.com/api/v1/exchanges"
    $hdrs = @{"X-API-KEY"=$xApiKey; "X-API-SECRET"=$xApiSec}
    $result = Invoke-RestMethod -Uri $URI -Method Post -Headers $hdrs
    return $result.data
  }
    
  #Get exchange Auth_ID
  $exch = (Get-ExchangeAuthID -exchange $Exchange -xApiKey $xApiKey -xApiSec $xApiSec)
  $auth_id = $exch.auth_id
  $exch_id = $exch.exch_id
    
  #Get exchange id and code
  $moreExch = ((get-exchange -xApiKey $xApiKey -xApiSec $xApiSec).data | Where-Object {$_.exch_id -eq $exch.exch_id}) | Select-Object exch_id,exch_code
  $moreExch
  
  #Get market information
  $marketInfo = Get-Market -exch_code ($moreExch.exch_code) -xApiKey $xApiKey -xApiSec $xApiSec
  $mktID = ($marketInfo | Where-Object {$_.mkt_name -eq $Market -And $_.exch_id -eq $exch_id}) | Select-Object -ExpandProperty mkt_id

  if ($mktID.Count -gt 1)
  {
    $mktID = $mktID[0] 
  }
  
  #Set up sell orders
  $allOrders = @()
  foreach ($level in $doublesTable){
    $prp = New-Object psobject 
    
    #order_type_id 2 specifies BUY order
    #price_type_id 3 specifies limit order
    $body = [ordered]@{
      'auth_id' = $auth_id
      'exch_id'= $exch_id
      'mkt_id'= $mktID
      'order_type_id' = 2
      'price_type_id'= 3
      'limit_price'= ($level.SellAt)
      'order_quantity'= ($level.amount)
    }
    
    Write-Output($body) 
    Start-Sleep -Seconds 1
    $order = set-order -body $body -xApiKey $xApiKey -xApiSec $xApiSec 
    
    $allOrders+=$order
  }
  $allOrders
}
