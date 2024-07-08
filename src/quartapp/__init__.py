import logging
import os

from quart import Quart

from .auth import auth


def create_app():
    if os.getenv("RUNNING_IN_PRODUCTION"):
        logging.basicConfig(level=logging.WARNING)
    else:
        logging.basicConfig(level=logging.INFO)

    app = Quart(__name__)
    app.config["SESSION_TYPE"] = "redis"
    app.logger.setLevel(logging.INFO)

    auth.init_app(app)

    from . import chat  # noqa

    app.register_blueprint(chat.bp)

    return app
