from flask import Blueprint, jsonify

health = Blueprint('health', __name__)


@health.route('/')
def check():
    return jsonify({"status": "healthy"}), 200
