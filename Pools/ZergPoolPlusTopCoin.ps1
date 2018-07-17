if (!(IsLoaded(".\Include.ps1"))) {. .\Include.ps1;RegisterLoaded(".\Include.ps1")}

Try {
    $Request = get-content ((split-path -parent (get-item $script:MyInvocation.MyCommand.Path).Directory) + "\BrainPlus\zergpoolplus\zergpoolplus.json") | ConvertFrom-Json
    $CoinsRequest = Invoke-WebRequest "http://api.zergpool.com:8080/api/currencies" -UseBasicParsing -Headers @{"Cache-Control" = "no-cache"} | ConvertFrom-Json 
}
catch { return }

if ((-not $Request) -or (-not $CoinsRequest)) {return}

$Name = (Get-Item $script:MyInvocation.MyCommand.Path).BaseName
$HostSuffix = ".mine.zergpool.com"
$PriceField = "actual_last24h"
# $PriceField = "estimate_current"
$DivisorMultiplier = 1000000
$Location = "US"

$ConfName = if ($Config.PoolsConfig.$Name -ne $Null){$Name}else{"default"}
$PoolConf = $Config.PoolsConfig.$ConfName

# Find bet coin fr each alga
$AllMiningCoins = @()
$TopMiningCoins = @()
($CoinsRequest | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name) | %{$CoinsRequest.$_ | Add-Member -Force @{Symbol = if ($CoinsRequest.$_.Symbol) {$CoinsRequest.$_.Symbol} else {$_}} ; $AllMiningCoins += $CoinsRequest.$_}
$Request | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name | ForEach-Object {
	$Algo = Get-Algorithm $Request.$_.Name
	$TopMiningCoins += $AllMiningCoins | where {($_.noautotrade -eq 0) -and ($_.hashrate -gt 0) -and ((Get-Algorithm $_.algo) -eq (Get-Algorithm $Algo))} | sort -Property @{Expression = {$_.$PriceField / ($DivisorMultiplier * [Double]$_.mbtc_mh_factor)}} -Descending | select -first 1
}
	$Variables.StatusText = $TopMiningCoins.Count

#Uses BrainPlus calculated price
$Request | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name | ForEach-Object {
    $PoolHost = "$($_)$($HostSuffix)"
    $PoolPort = $Request.$_.port
    $PoolAlgorithm = Get-Algorithm $Request.$_.name

    $Divisor = $DivisorMultiplier * [Double]$Request.$_.mbtc_mh_factor

    if ((Get-Stat -Name "$($Name)_$($PoolAlgorithm)_Profit") -eq $null) {$Stat = Set-Stat -Name "$($Name)_$($PoolAlgorithm)_Profit" -Value ([Double]$Request.$_.$PriceField / $Divisor * (1 - ($Request.$_.fees / 100)))}
    else {$Stat = Set-Stat -Name "$($Name)_$($PoolAlgorithm)_Profit" -Value ([Double]$Request.$_.$PriceField / $Divisor * (1 - ($Request.$_.fees / 100)))}

	$PwdCurr = if ($PoolConf.PwdCurrency) {$PoolConf.PwdCurrency}else {$Config.Passwordcurrency}
    $WorkerName = If ($PoolConf.WorkerName -like "ID=*") {$PoolConf.WorkerName} else {"ID=$($PoolConf.WorkerName)"}
	
    if ($PoolConf.Wallet) {
        [PSCustomObject]@{
            Algorithm     = $PoolAlgorithm
            Coin          = ($TopMiningCoins | where {$_.algo -eq $_}).Symbol
            Info          = ($TopMiningCoins | where {$_.algo -eq $_}).Name
            Price         = $Stat.Live*$PoolConf.PricePenaltyFactor
            StablePrice   = $Stat.Week
            MarginOfError = $Stat.Week_Fluctuation
            Protocol      = "stratum+tcp"
            Host          = $PoolHost
            Port          = $PoolPort
            User          = $PoolConf.Wallet
		    Pass          = "$($WorkerName),c=$($PwdCurr),mc=$(($TopMiningCoins | where {$_.algo -eq $_}).Symbol)"
            Location      = $Location
            SSL           = $false
        }
    }
}
