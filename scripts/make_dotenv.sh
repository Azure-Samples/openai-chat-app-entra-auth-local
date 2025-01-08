echo "AZURE_OPENAI_ENDPOINT=$(azd env get-value AZURE_OPENAI_ENDPOINT)"
echo "AZURE_OPENAI_API_VERSION=$(azd env get-value AZURE_OPENAI_API_VERSION)"
echo "AZURE_OPENAI_CHATGPT_DEPLOYMENT=$(azd env get-value AZURE_OPENAI_CHATGPT_DEPLOYMENT)"
echo "AZURE_AUTH_AUTHORITY=$(azd env get-value AZURE_AUTH_AUTHORITY)"
echo "AZURE_AUTH_CLIENT_ID=$(azd env get-value AZURE_AUTH_CLIENT_ID)"
echo "AZURE_AUTH_CLIENT_SECRET_NAME=$(azd env get-value AZURE_AUTH_CLIENT_SECRET_NAME)"
echo "AZURE_KEY_VAULT_NAME=$(azd env get-value AZURE_KEY_VAULT_NAME)"

# Save the output to a file named `.env`
# Run this script with `sh scripts/make_dotenv.sh > .env`
