---
name: OpenAI Chat Application with Microsoft Entra Authentication
description: A simple chat application that integrates Microsoft Entra for user authentication. Designed for deployment on Azure Container Apps with the Azure Developer CLI.
languages:
- azdeveloper
- python
- bicep
- html
products:
- azure
- azure-container-apps
- azure-openai
- azure-container-registry
- entra-id
page_type: sample
urlFragment: openai-chat-app-entra-auth-local
---
<!-- YAML front-matter schema: https://review.learn.microsoft.com/en-us/help/contribute/samples/process/onboarding?branch=main#supported-metadata-fields-for-readmemd -->


This repository includes a Python app that uses Azure OpenAI to generate responses to user messages, and Microsoft Entra for user authentication.

The project includes all the infrastructure and configuration needed to setup Microsoft Entra authentication, provision Azure OpenAI resources (with keyless access), and deploy the app to [Azure Container Apps](https://learn.microsoft.com/azure/container-apps/overview) using the [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/overview).


For instructions on deploying this project to Azure, please refer to the [README on GitHub](https://github.com/Azure-Samples/openai-chat-app-entra-auth-local/?tab=readme-ov-file).
