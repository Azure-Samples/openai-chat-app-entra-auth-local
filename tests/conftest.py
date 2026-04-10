from dataclasses import dataclass
from functools import wraps

import identity.quart
import pytest
import pytest_asyncio
from azure.keyvault.secrets.aio import SecretClient

import quartapp

from . import mock_cred


@pytest.fixture
def mock_openai_responses_stream(monkeypatch):
    @dataclass
    class MockResponseEvent:
        type: str
        delta: str | None = None

        def model_dump(self) -> dict[str, str]:
            payload = {"type": self.type}
            if self.delta is not None:
                payload["delta"] = self.delta
            return payload

    class AsyncResponseStream:
        def __init__(self, answer: str):
            self._chunk_index = 0
            self._chunks = []
            for answer_index, answer_delta in enumerate(answer.split(" ")):
                if answer_index > 0:
                    answer_delta = " " + answer_delta
                self._chunks.append(MockResponseEvent(type="response.output_text.delta", delta=answer_delta))

        def __aiter__(self):
            return self

        async def __anext__(self):
            if self._chunk_index < len(self._chunks):
                next_chunk = self._chunks[self._chunk_index]
                self._chunk_index += 1
                return next_chunk
            raise StopAsyncIteration

    class AsyncResponseStreamManager:
        def __init__(self, answer: str):
            self._stream = AsyncResponseStream(answer)

        async def __aenter__(self):
            return self._stream

        async def __aexit__(self, exc_type, exc, exc_tb):
            return None

    def mock_stream(*args, **kwargs):
        response_input = kwargs.get("input")
        last_message = response_input[-1]["content"][0]["text"]

        assert response_input[0] == {
            "type": "message",
            "role": "system",
            "content": [{"type": "input_text", "text": "You are a helpful assistant."}],
        }

        if len(response_input) > 2:
            assistant_message = response_input[-2]
            assert assistant_message["role"] == "assistant"
            assert assistant_message["content"][0]["type"] == "output_text"

        assert kwargs.get("store") is False
        if last_message == "What is the capital of France?":
            return AsyncResponseStreamManager("The capital of France is Paris.")
        if last_message == "What is the capital of Germany?":
            return AsyncResponseStreamManager("The capital of Germany is Berlin.")
        raise ValueError(f"Unexpected message: {last_message}")

    monkeypatch.setattr("openai.resources.responses.responses.AsyncResponses.stream", mock_stream)


@pytest.fixture
def mock_defaultazurecredential(monkeypatch):
    monkeypatch.setattr("azure.identity.aio.DefaultAzureCredential", mock_cred.MockAzureCredential)


@pytest.fixture
def mock_keyvault_secretclient(monkeypatch):
    monkeypatch.setattr("quartapp.load_dotenv", lambda *args, **kwargs: None)
    monkeypatch.setenv("AZURE_KEY_VAULT_NAME", "my_key_vault")
    monkeypatch.setenv("AZURE_AUTH_CLIENT_SECRET_NAME", "my_secret_name")

    async def get_secret(*args, **kwargs):
        if args[1] == "my_secret_name":
            return mock_cred.MockKeyVaultSecret("mysecret")
        raise Exception(f"Unexpected secret name: {args[1]}")

    monkeypatch.setattr(SecretClient, "get_secret", get_secret)


@pytest.fixture
def mock_login_required(monkeypatch):
    def login_required(self, f):
        context = {
            "user": {
                "name": "Namey McNameface",
                # Other fields have been omitted for brevity
            }
        }

        @wraps(f)
        async def decorated_function(*args, **kwargs):
            return await f(*args, context=context, **kwargs)

        return decorated_function

    monkeypatch.setattr(identity.quart.Auth, "login_required", login_required)


@pytest_asyncio.fixture
async def client(
    monkeypatch,
    mock_openai_responses_stream,
    mock_defaultazurecredential,
    mock_keyvault_secretclient,
    mock_login_required,
):
    monkeypatch.setenv("AZURE_OPENAI_ENDPOINT", "test-openai-service.openai.azure.com")
    monkeypatch.setenv("AZURE_OPENAI_CHATGPT_DEPLOYMENT", "test-chatgpt")

    quart_app = quartapp.create_app()

    async with quart_app.test_app() as test_app:
        quart_app.config.update({"TESTING": True})

        yield test_app.test_client()
