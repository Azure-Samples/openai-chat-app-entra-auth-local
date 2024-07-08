import os
import logging

import azure.identity
from azure.keyvault.secrets import SecretClient
from identity.quart import Auth

def get_redirect_uri():
    redirect_uri = "http://localhost:50505/redirect"
    if os.getenv("RUNNING_IN_PRODUCTION"):
        redirect_uri = (
            f"https://{os.environ['CONTAINER_APP_NAME']}.{os.environ['CONTAINER_APP_ENV_DNS_SUFFIX']}/redirect"
        )
        logging.warn(f"Using production redirect URI: {redirect_uri}")
    return redirect_uri

def get_auth_client_secret():
    AZURE_AUTH_CLIENT_SECRET_NAME = os.getenv("AZURE_AUTH_CLIENT_SECRET_NAME")
    AZURE_KEY_VAULT_NAME = os.getenv("AZURE_KEY_VAULT_NAME")
    azure_credential = azure.identity.DefaultAzureCredential(exclude_shared_token_cache_credential=True)
    key_vault_client = SecretClient(vault_url=f"https://{AZURE_KEY_VAULT_NAME}.vault.azure.net", credential=azure_credential)
    auth_client_secret = (key_vault_client.get_secret(AZURE_AUTH_CLIENT_SECRET_NAME)).value
    return auth_client_secret

auth = Auth(
    app=None,
    authority=os.getenv("AZURE_AUTH_AUTHORITY"),
    client_id=os.getenv("AZURE_AUTH_CLIENT_ID"),
    client_credential=get_auth_client_secret(),
    redirect_uri=get_redirect_uri(),
)

