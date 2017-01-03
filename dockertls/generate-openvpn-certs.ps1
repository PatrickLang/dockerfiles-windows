$ErrorActionPreference = "Stop"

$Global:SSLCARoot = "c:\CARoot\"
$Global:caPrivateKeyPassFile = ($Global:SSLCARoot + "ca-key-pass.txt")
$Global:caPrivateKeyPass = ""
$Global:caPrivateKeyFile = ($Global:SSLCARoot + "ca-key.pem")
$Global:caPublicKeyFile = ($Global:SSLCARoot + "ca.pem")

$Global:UserCertPath = "c:\UserCert\"
$Global:ServerCertPath = "c:\ServerCert\"

$Global:ServerName = $ENV:CN_Server
# $Global:ClientName = $ENV:CN_Client # TODO if needed

function ensureDirs($dirs) {
  foreach ($dir in $dirs) {
    if (!(Test-Path $dir)) {
      mkdir $dir
    }
  }
}

# https://docs.docker.com/engine/security/https/
function createCA(){
  Write-Host "`n=== Generating CA private password"
  $Global:caPrivateKeyPass = "pass:$(openssl rand -base64 32)"

  Write-Host "`n=== Writing out private key password"
  $Global:caPrivateKeyPass | Out-File -FilePath $Global:caPrivateKeyPassFile

  Write-Host "`n=== Generating CA private key"
  & openssl genrsa -aes256 -passout $Global:caPrivateKeyPass -out $Global:caPrivateKeyFile 4096

  Write-Host "`n=== Generating CA public key"
  & openssl req -subj "/C=US/ST=Washington/L=Redmond/O=./OU=." -new -x509 -days 365 -passin $Global:caPrivateKeyPass -key $Global:caPrivateKeyFile -sha256 -out $Global:caPublicKeyFile
}

# https://docs.docker.com/engine/security/https/
function createCerts($certsPath, $userPath, $serverName) {
  Write-Host "`n=== Reading in CA Private Key Password"
  $Global:caPrivateKeyPass = Get-Content -Path $Global:caPrivateKeyPassFile

  Write-Host "`n=== Generating Server private key"
  & openssl genrsa -out server-key.pem 4096

  Write-Host "`n=== Generating Server signing request"
  & openssl req -subj "/CN=$serverName/" -sha256 -new -key server-key.pem -out server.csr

  Write-Host "`n=== Signing Server request"
  & openssl x509 -req -days 365 -sha256 -in server.csr -CA $Global:caPublicKeyFile -passin $Global:caPrivateKeyPass -CAkey $Global:caPrivateKeyFile `
    -CAcreateserial -out server-cert.pem

  Write-Host "`n=== Generating Client key"
  & openssl genrsa -out key.pem 4096

  Write-Host "`n=== Generating Client signing request"
  & openssl req -subj '/CN=client' -new -key key.pem -out client.csr

  Write-Host "`n=== Signing Client signing request"
  "extendedKeyUsage = clientAuth" | Out-File extfile.cnf -Encoding Ascii
  & openssl x509 -req -days 365 -sha256 -in client.csr -CA $Global:caPublicKeyFile -passin $Global:caPrivateKeyPass -CAkey $Global:caPrivateKeyFile `
    -CAcreateserial -out cert.pem -extfile extfile.cnf

  Write-Host "`n=== Copying Server certificates to $certsPath"
  copy $Global:caPublicKeyFile $certsPath\ca.pem
  copy server-cert.pem $certsPath\server-cert.pem
  copy server-key.pem $certsPath\server-key.pem

  Write-Host "`n=== Copying Client certificates to $userPath"
  copy $Global:caPublicKeyFile $userPath\ca.pem
  copy cert.pem $userPath\cert.pem
  copy key.pem $userPath\key.pem
}


ensureDirs @($Global:ServerCertPath, $Global:UserCertPath, $Global:CARoot)

#Test the CA Root path to see if an existing set of CA keys was provided
if (  !(Test-Path -Path $Global:caPrivateKeyPassFile) -or 
      !( Test-Path -Path $Global:caPrivateKeyFile) -or
      !( Test-Path -Path $Global:caPrivateKeyPassFile) 
   )
{
  createCA
}

createCerts $Global:ServerCertPath $Global:UserCertPath $serverName
