import asyncio
import os
import subprocess

from azure.identity import AzureDeveloperCliCredential
from msgraph import GraphServiceClient
from msgraph.generated.models.application import Application
from msgraph.generated.models.web_application import WebApplication


async def update_redirect_uris(client: GraphServiceClient, app_id: str, uri: str):
    request_body = Application(
        web=WebApplication(redirect_uris=["http://localhost:50505/redirect", uri]),
    )
    await client.applications.by_application_id(app_id).patch(request_body)


async def main():
    print("Clearing secret from environment (now that it's stored in KeyVault)...")
    subprocess.run('azd env set AZURE_AUTH_CLIENT_SECRET ""', shell=True)

    print("Updating authentication...")
    credential = AzureDeveloperCliCredential(tenant_id=os.getenv("AZURE_AUTH_TENANT_ID"))
    scopes = ["https://graph.microsoft.com/.default"]
    client = GraphServiceClient(credentials=credential, scopes=scopes)

    app_id = os.getenv("AZURE_AUTH_APP_ID")
    uri = os.getenv("AZURE_AUTH_REDIRECT_URI")
    print(f"Updating application registration {app_id} with redirect URI for {uri}")
    await update_redirect_uris(client, app_id, uri)


if __name__ == "__main__":
    asyncio.run(main())
