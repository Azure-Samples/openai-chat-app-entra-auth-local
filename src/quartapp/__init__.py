import logging
import os

from quart import Quart


def create_app():
    if os.getenv("RUNNING_IN_PRODUCTION"):
        logging.basicConfig(level=logging.WARNING)
    else:
        logging.basicConfig(level=logging.INFO)

    app = Quart(__name__)
    app.logger.setLevel(logging.INFO)

    from .auth import auth

    # Declare the session type first, for the Auth extension to work with Quart-Session properly:
    app.config["SESSION_TYPE"] = "redis"
    # Initialize the Auth extension with the Quart app instance:
    auth.init_app(app)

    from . import chat  # noqa

    app.register_blueprint(chat.bp)

    return app
