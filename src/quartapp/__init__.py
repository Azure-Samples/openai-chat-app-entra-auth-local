import logging
import os

from dotenv import load_dotenv
from quart import Quart


def create_app():
    if os.getenv("RUNNING_IN_PRODUCTION"):
        logging.basicConfig(level=logging.WARNING)
    else:
        logging.basicConfig(level=logging.INFO)
        load_dotenv(verbose=True, override=True)

    app = Quart(__name__)
    app.logger.setLevel(logging.INFO)

    from . import chat  # noqa

    app.register_blueprint(chat.bp)

    return app
