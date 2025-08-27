## Commands to bootstrap an empty Hashicorp Vault instance and generate UEFI Secure Boot keys, prior to running sign_disk_image.sh
##
## A test Vault instance can be started locally
## docker run --cap-add=IPC_LOCK -e 'VAULT_LOCAL_CONFIG={"storage": {"file": {"path": "/vault/file"}}, "listener": [{"tcp": { "address": "0.0.0.0:8200", "tls_disable": true}}], "default_lease_ttl": "168h", "max_lease_ttl": "720h", "ui": true}' -p 8200:8200 hashicorp/vault server

export VAULT_ADDR='http://127.0.0.1:8200' # Production setup should use TLS

vault operator init -key-shares=1 -key-threshold=1
# ...save unseal key and root token...

vault operator unseal
vault login

# > Success! You are now authenticated. The token information displayed below
# > is already stored in the token helper. You do NOT need to run "vault login"
# > again. Future Vault requests will automatically use this token.

vault secrets enable transit

vault write -f transit/keys/PK type=rsa-4096
vault write -f transit/keys/KEK type=rsa-4096
vault write -f transit/keys/db type=rsa-4096

vault secrets enable pki
vault secrets tune -max-lease-ttl=365d pki

vault write pki/roles/root allow_any_name=true server_flag=false client_flag=false code_signing_flag=true key_usage=''

vault write pki/keys/generate/internal key_name=ca-key
vault write pki/root/generate/internal issuer_name=new-ca key_ref=ca-key ttl=365d common_name="Vault CA"