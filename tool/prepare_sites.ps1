param(
  [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..'))
)

$dist = Join-Path $ProjectRoot 'dist'
$client = Join-Path $dist 'client'
$server = Join-Path $dist 'server'
$metadata = Join-Path $dist '.openai'

if (Test-Path -LiteralPath $dist) {
  Remove-Item -LiteralPath $dist -Recurse -Force
}

New-Item -ItemType Directory -Path $client, $server, $metadata | Out-Null
Copy-Item -Path (Join-Path $ProjectRoot 'build\web\*') -Destination $client -Recurse
Copy-Item -LiteralPath (Join-Path $ProjectRoot 'site\worker.js') `
  -Destination (Join-Path $server 'index.js')
Copy-Item -LiteralPath (Join-Path $ProjectRoot '.openai\hosting.json') `
  -Destination (Join-Path $metadata 'hosting.json')
