import json
import os
import time
from functools import wraps

import azure.identity.aio
import openai
import redis.asyncio as redis
from quart import (
    Blueprint,
    Response,
    current_app,
    render_template,
    request,
    stream_with_context,
)

from .auth import auth

bp = Blueprint("chat", __name__, template_folder="templates", static_folder="static")


def get_azure_credential():
    if not hasattr(bp, "azure_credential"):
        bp.azure_credential = azure.identity.aio.DefaultAzureCredential(exclude_shared_token_cache_credential=True)
    return bp.azure_credential


@bp.before_app_serving
async def configure_clients():
    client_args = {}
    if os.getenv("LOCAL_OPENAI_ENDPOINT"):
        # Use a local endpoint like llamafile server
        current_app.logger.info("Using local OpenAI-compatible API with no key")
        client_args["api_key"] = "no-key-required"
        client_args["base_url"] = os.getenv("LOCAL_OPENAI_ENDPOINT")
        bp.openai_client = openai.AsyncOpenAI(
            **client_args,
        )
    else:
        # Use an Azure OpenAI endpoint instead,
        # either with a key or with keyless authentication
        if os.getenv("AZURE_OPENAI_KEY"):
            # Authenticate using an Azure OpenAI API key
            # This is generally discouraged, but is provided for developers
            # that want to develop locally inside the Docker container.
            current_app.logger.info("Using Azure OpenAI with key")
            client_args["api_key"] = os.getenv("AZURE_OPENAI_KEY")
        else:
            # Authenticate using the default Azure credential chain
            # See https://docs.microsoft.com/azure/developer/python/azure-sdk-authenticate#defaultazurecredential
            # This will *not* work inside a Docker container.
            current_app.logger.info("Using Azure OpenAI with default credential")
            client_args["azure_ad_token_provider"] = azure.identity.aio.get_bearer_token_provider(
                get_azure_credential(), "https://cognitiveservices.azure.com/.default"
            )
        if not os.getenv("AZURE_OPENAI_ENDPOINT"):
            raise ValueError("AZURE_OPENAI_ENDPOINT is required for Azure OpenAI")
        if not os.getenv("AZURE_OPENAI_CHATGPT_DEPLOYMENT"):
            raise ValueError("AZURE_OPENAI_CHATGPT_DEPLOYMENT is required for Azure OpenAI")
        bp.openai_client = openai.AsyncAzureOpenAI(
            api_version=os.getenv("AZURE_OPENAI_API_VERSION") or "2024-02-15-preview",
            azure_endpoint=os.getenv("AZURE_OPENAI_ENDPOINT"),
            **client_args,
        )

    bp.cache = await setup_redis()
    current_app.config["SESSION_REDIS"] = bp.cache


async def setup_redis():
    azure_scope = "https://redis.azure.com/.default"
    use_azure_redis = os.getenv("RUNNING_IN_PRODUCTION") is not None
    if use_azure_redis:
        host = os.getenv("AZURE_REDIS_HOST")
        bp.redis_username = os.getenv("AZURE_REDIS_USER")
        port = 6380
        ssl = True
    else:
        host = "localhost"
        port = 6379
        bp.redis_username = None
        password = None
        ssl = False

    if use_azure_redis:
        current_app.logger.info("Using Azure Redis with default credential")
        bp.redis_token = await get_azure_credential().get_token(azure_scope)
        password = bp.redis_token.token
    else:
        current_app.logger.info("Using Redis with username and password")

    return redis.Redis(
        host=host, ssl=ssl, port=port, username=bp.redis_username, password=password, decode_responses=True
    )


@bp.before_request
async def ensure_redis_token():
    if not hasattr(bp, "redis_token"):
        return
    redis_cache = bp.cache
    redis_token = bp.redis_token
    if redis_token.expires_on < time.time() + 60:
        current_app.logger.info("Refreshing token...")
        tmp_token = await get_azure_credential().get_token("https://redis.azure.com/.default")
        if tmp_token:
            azure_token = tmp_token
        await redis_cache.execute_command("AUTH", bp.redis_username, azure_token.token)
        current_app.logger.info("Successfully refreshed token.")


@bp.after_app_serving
async def shutdown_openai():
    await bp.openai_client.close()
    await bp.azure_credential.close()


@bp.get("/")
@auth.login_required
async def index(*, context):
    return await render_template("index.html", user=context["user"]["name"])


@bp.post("/chat/stream")
@auth.login_required
async def chat_handler(*, context):
    request_messages = (await request.get_json())["messages"]

    @stream_with_context
    async def response_stream():
        # This sends all messages, so API request may exceed token limits
        all_messages = [
            {"role": "system", "content": "You are a helpful assistant."},
        ] + request_messages

        chat_coroutine = bp.openai_client.chat.completions.create(
            # Azure Open AI takes the deployment name as the model name
            model=os.environ["AZURE_OPENAI_CHATGPT_DEPLOYMENT"],
            messages=all_messages,
            stream=True,
        )
        try:
            async for event in await chat_coroutine:
                event_dict = event.model_dump()
                if event_dict["choices"]:
                    yield json.dumps(event_dict["choices"][0], ensure_ascii=False) + "\n"
        except Exception as e:
            current_app.logger.error(e)
            yield json.dumps({"error": str(e)}, ensure_ascii=False) + "\n"

    return Response(response_stream())
