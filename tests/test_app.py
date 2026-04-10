import pytest

import quartapp


@pytest.mark.asyncio
async def test_index(client):
    response = await client.get("/")
    assert response.status_code == 200
    assert b"Namey McNameface" in await response.get_data()


@pytest.mark.asyncio
async def test_chat_stream_text(client, snapshot):
    response = await client.post(
        "/chat/stream",
        json={
            "input": [
                {
                    "type": "message",
                    "role": "system",
                    "content": [{"type": "input_text", "text": "You are a helpful assistant."}],
                },
                {
                    "type": "message",
                    "role": "user",
                    "content": [{"type": "input_text", "text": "What is the capital of France?"}],
                },
            ]
        },
    )
    assert response.status_code == 200
    result = await response.get_data()
    snapshot.assert_match(result, "result.jsonlines")


@pytest.mark.asyncio
async def test_chat_stream_text_history(client, snapshot):
    response = await client.post(
        "/chat/stream",
        json={
            "input": [
                {
                    "type": "message",
                    "role": "system",
                    "content": [{"type": "input_text", "text": "You are a helpful assistant."}],
                },
                {
                    "type": "message",
                    "role": "user",
                    "content": [{"type": "input_text", "text": "What is the capital of France?"}],
                },
                {
                    "type": "message",
                    "role": "assistant",
                    "content": [{"type": "output_text", "text": "Paris"}],
                },
                {
                    "type": "message",
                    "role": "user",
                    "content": [{"type": "input_text", "text": "What is the capital of Germany?"}],
                },
            ]
        },
    )
    assert response.status_code == 200
    result = await response.get_data()
    snapshot.assert_match(result, "result.jsonlines")


@pytest.mark.asyncio
async def test_openai_key(monkeypatch, mock_keyvault_secretclient):
    monkeypatch.setenv("AZURE_OPENAI_KEY", "test-key")
    monkeypatch.setenv("AZURE_OPENAI_ENDPOINT", "test-openai-service.openai.azure.com")
    monkeypatch.setenv("AZURE_OPENAI_CHATGPT_DEPLOYMENT", "test-chatgpt")

    quart_app = quartapp.create_app()

    async with quart_app.test_app():
        assert quart_app.blueprints["chat"].openai_client.api_key == "test-key"
        base_url = str(quart_app.blueprints["chat"].openai_client.base_url).rstrip("/")
        assert base_url == "test-openai-service.openai.azure.com/openai/v1"


@pytest.mark.asyncio
async def test_openai_managedidentity(monkeypatch, mock_keyvault_secretclient):
    monkeypatch.setenv("AZURE_CLIENT_ID", "test-client-id")
    monkeypatch.setenv("AZURE_OPENAI_ENDPOINT", "test-openai-service.openai.azure.com")
    monkeypatch.setenv("AZURE_OPENAI_CHATGPT_DEPLOYMENT", "test-chatgpt")

    quart_app = quartapp.create_app()

    async with quart_app.test_app():
        # For managed identity, the api_key will be the token provider function
        assert quart_app.blueprints["chat"].openai_client.api_key is not None
        base_url = str(quart_app.blueprints["chat"].openai_client.base_url).rstrip("/")
        assert base_url == "test-openai-service.openai.azure.com/openai/v1"


@pytest.mark.asyncio
async def test_openai_local(monkeypatch, mock_keyvault_secretclient):
    monkeypatch.setenv("LOCAL_OPENAI_ENDPOINT", "http://localhost:8080")

    quart_app = quartapp.create_app()

    async with quart_app.test_app():
        assert quart_app.blueprints["chat"].openai_client.api_key == "no-key-required"
        assert quart_app.blueprints["chat"].openai_client.base_url == "http://localhost:8080"
