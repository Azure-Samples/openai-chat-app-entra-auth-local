 #!/bin/sh

if [ -n "$GITHUB_ACTIONS" ]; then
  echo "This script does not currently work in GitHub Actions. Please run azd up locally first to set up Microsoft Entra application registration."
  exit 0
fi

. ./scripts/load_env.sh

python ./scripts/auth_update.py
