import azure.core.credentials_async


class MockAsyncAzureCredential(azure.core.credentials_async.AsyncTokenCredential):
    pass


class MockAzureCredential(azure.core.credentials.TokenCredential):
    pass


class MockKeyVaultSecret:
    def __init__(self, value):
        self.value = value
