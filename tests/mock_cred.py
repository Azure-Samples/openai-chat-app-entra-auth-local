import azure.core.credentials_async


class MockAzureCredential(azure.core.credentials_async.AsyncTokenCredential):
    pass


class MockKeyVaultSecret:
    def __init__(self, value):
        self.value = value
