param(
    [string]$Experiment = "network/latency-order-service",
    [switch]$TearDown
)

$RepoRoot     = Split-Path $PSScriptRoot -Parent
$ClusterName  = "chaos-local"

# Convert Windows path to Git Bash format: C:\Users\... -> /c/Users/...
$drive        = $RepoRoot.Substring(0,1).ToLower()
$rest         = $RepoRoot.Substring(2).Replace('\','/')
$RepoRootBash = "/$drive$rest"

# Add known tool locations to PATH for this session
$toolPaths = @("C:\Helm", "C:\Helm\windows-amd64")
foreach ($p in $toolPaths) {
    if ((Test-Path $p) -and ($env:Path -notlike "*$p*")) {
        $env:Path += ";$p"
    }
}

function Check-Tool($cmd) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Write-Host "  MISSING: $cmd" -ForegroundColor Red
        return $false
    }
    Write-Host "  OK: $cmd" -ForegroundColor Green
    return $true
}

# Tear down
if ($TearDown) {
    Write-Host "Tearing down cluster $ClusterName ..." -ForegroundColor Yellow
    kind delete cluster --name $ClusterName
    Write-Host "Done." -ForegroundColor Green
    exit 0
}

# Check prerequisites
Write-Host "Checking prerequisites..." -ForegroundColor Cyan
$ok = $true
$ok = (Check-Tool "docker")  -and $ok
$ok = (Check-Tool "kind")    -and $ok
$ok = (Check-Tool "kubectl") -and $ok
$ok = (Check-Tool "helm")    -and $ok
$ok = (Check-Tool "bash")    -and $ok

if (-not $ok) {
    Write-Host "Install the missing tools then re-run." -ForegroundColor Red
    Write-Host "  kind : https://kind.sigs.k8s.io/docs/user/quick-start"
    Write-Host "  helm : https://helm.sh/docs/intro/install"
    Write-Host "  bash : comes with Git for Windows"
    exit 1
}

# Check Docker is running
$null = docker ps 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "Docker is not running. Start Docker Desktop first." -ForegroundColor Red
    exit 1
}
Write-Host "  OK: Docker is running" -ForegroundColor Green

# Create cluster if needed
$clusters = kind get clusters 2>&1
if ($clusters -notcontains $ClusterName) {
    Write-Host "Creating kind cluster $ClusterName (2-3 min first time)..." -ForegroundColor Cyan
    bash "$RepoRootBash/scripts/local-setup.sh"
} else {
    Write-Host "Cluster $ClusterName already exists." -ForegroundColor Green
    kubectl config use-context "kind-$ClusterName" | Out-Null
}

# Wait for Prometheus
Write-Host "Waiting for Prometheus..." -ForegroundColor Cyan
kubectl rollout status deployment/prometheus-server -n observability --timeout=120s

# Port-forward Prometheus in background
Write-Host "Starting Prometheus port-forward..." -ForegroundColor Cyan
$pfJob = Start-Job -ScriptBlock {
    kubectl port-forward -n observability svc/prometheus-server 9090:80
}
Start-Sleep -Seconds 4

try {
    $null = Invoke-WebRequest "http://localhost:9090/-/healthy" -UseBasicParsing -TimeoutSec 5
    Write-Host "  Prometheus ready at http://localhost:9090" -ForegroundColor Green
} catch {
    Write-Host "  Prometheus not responding yet, waiting 10s..." -ForegroundColor Yellow
    Start-Sleep -Seconds 10
}

# Run the experiment
$manifestPath = "chaos-mesh/experiments/$Experiment.yaml"
Write-Host "Running experiment: $manifestPath" -ForegroundColor Cyan
$env:PROMETHEUS_URL = "http://localhost:9090"
bash "$RepoRootBash/scripts/run-experiment.sh" "$manifestPath"

# Cleanup
Stop-Job  $pfJob -ErrorAction SilentlyContinue
Remove-Job $pfJob -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Done. Cluster is still running." -ForegroundColor Green
Write-Host "  Next experiment : .\scripts\local-test.ps1 -Experiment pod/pod-kill-order-service"
Write-Host "  Tear down       : .\scripts\local-test.ps1 -TearDown"
