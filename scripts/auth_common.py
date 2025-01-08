import logging
import subprocess

from dotenv import load_dotenv

logger = logging.getLogger("authsetup")


def load_azd_env():
    """Get path to current azd env file and load file using python-dotenv"""
    result = subprocess.run(
        'azd env list --query "[?IsDefaultt].DotEnvPath | [0]" -o json', shell=True, stdout=subprocess.PIPE, text=True
    )
    if result.returncode != 0:
        raise Exception("Error loading azd env")
    env_file_path = result.stdout
    print(f"path:{env_file_path}:")
    print(len(env_file_path))
    if not env_file_path:
        raise Exception("No default azd env file found")
    logger.info(f"Loading azd env from {env_file_path}")
    load_dotenv(env_file_path, override=True)
