"""A tiny web app used to test the pipeline end to end."""
import os
import socket

from flask import Flask, jsonify

app = Flask(__name__)
VERSION = os.environ.get("APP_VERSION", "dev")


@app.route("/")
def index():
    return (
        "<h1>Infrastructure as Code Lab</h1>"
        f"<p>Version: {VERSION}</p>"
        f"<p>Served by: {socket.gethostname()}</p>"
    )


@app.route("/health")
def health():
    return jsonify(status="ok", version=VERSION)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
