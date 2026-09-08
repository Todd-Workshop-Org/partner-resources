"""
Mock Port.io Integration Server

This service mimics an external system integration for Port.io.
It provides two endpoints that return realistic Port entity payloads
for an Ocean integration to consume and send to Port.
"""

from flask import Flask, jsonify, request
from datetime import datetime, timedelta
import logging
import os

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Configuration from environment
SERVICE_NAME = os.getenv("SERVICE_NAME", "Mock Integration")
ENVIRONMENT = os.getenv("ENVIRONMENT", "development")
PORT = int(os.getenv("PORT", 5000))


def generate_services():
    """Generate mock microservice/application data."""
    return [
        {
            "id": "svc-api-gateway",
            "name": "API Gateway",
            "type": "service",
            "status": "healthy",
            "team": "Platform",
            "language": "Go",
            "repository": "https://github.com/example/api-gateway",
            "deployments": 1247,
            "uptime": 99.98,
            "last_deployment": (datetime.now() - timedelta(hours=2)).isoformat(),
            "created_at": (datetime.now() - timedelta(days=180)).isoformat(),
            "tags": ["critical", "production", "platform"],
        },
        {
            "id": "svc-auth-service",
            "name": "Auth Service",
            "type": "service",
            "status": "healthy",
            "team": "Security",
            "language": "Python",
            "repository": "https://github.com/example/auth-service",
            "deployments": 892,
            "uptime": 99.99,
            "last_deployment": (datetime.now() - timedelta(days=1)).isoformat(),
            "created_at": (datetime.now() - timedelta(days=365)).isoformat(),
            "tags": ["critical", "production", "security"],
        },
        {
            "id": "svc-user-api",
            "name": "User API",
            "type": "service",
            "status": "degraded",
            "team": "Backend",
            "language": "Node.js",
            "repository": "https://github.com/example/user-api",
            "deployments": 654,
            "uptime": 99.45,
            "last_deployment": (datetime.now() - timedelta(hours=6)).isoformat(),
            "created_at": (datetime.now() - timedelta(days=90)).isoformat(),
            "tags": ["core", "production"],
        },
        {
            "id": "svc-notification-service",
            "name": "Notification Service",
            "type": "service",
            "status": "healthy",
            "team": "Backend",
            "language": "Java",
            "repository": "https://github.com/example/notification-service",
            "deployments": 423,
            "uptime": 99.87,
            "last_deployment": (datetime.now() - timedelta(hours=12)).isoformat(),
            "created_at": (datetime.now() - timedelta(days=120)).isoformat(),
            "tags": ["production"],
        },
        {
            "id": "svc-analytics-worker",
            "name": "Analytics Worker",
            "type": "service",
            "status": "healthy",
            "team": "Data",
            "language": "Python",
            "repository": "https://github.com/example/analytics-worker",
            "deployments": 312,
            "uptime": 98.92,
            "last_deployment": (datetime.now() - timedelta(hours=24)).isoformat(),
            "created_at": (datetime.now() - timedelta(days=60)).isoformat(),
            "tags": ["production", "data-pipeline"],
        },
    ]


def generate_incidents():
    """Generate mock incident/alert data."""
    return [
        {
            "id": "inc-2024-001",
            "title": "High latency in API Gateway",
            "description": "P1 incident: API response times elevated above threshold",
            "severity": "critical",
            "status": "investigating",
            "service_id": "svc-api-gateway",
            "team": "Platform",
            "created_at": (datetime.now() - timedelta(hours=1)).isoformat(),
            "started_at": (datetime.now() - timedelta(hours=1, minutes=15)).isoformat(),
            "assignee": "alice@example.com",
            "tags": ["performance", "incident"],
        },
        {
            "id": "inc-2024-002",
            "title": "Increased error rate in User API",
            "description": "5xx errors above baseline - degraded service",
            "severity": "high",
            "status": "investigating",
            "service_id": "svc-user-api",
            "team": "Backend",
            "created_at": (datetime.now() - timedelta(hours=2)).isoformat(),
            "started_at": (datetime.now() - timedelta(hours=2, minutes=30)).isoformat(),
            "assignee": "bob@example.com",
            "tags": ["errors", "incident"],
        },
        {
            "id": "inc-2024-003",
            "title": "Database connection pool exhaustion",
            "description": "Analytics worker cannot obtain DB connections",
            "severity": "high",
            "status": "resolved",
            "service_id": "svc-analytics-worker",
            "team": "Data",
            "created_at": (datetime.now() - timedelta(hours=6)).isoformat(),
            "started_at": (datetime.now() - timedelta(hours=6, minutes=45)).isoformat(),
            "resolved_at": (datetime.now() - timedelta(hours=5, minutes=30)).isoformat(),
            "assignee": "charlie@example.com",
            "tags": ["database", "incident"],
        },
        {
            "id": "inc-2024-004",
            "title": "Disk space warning on production",
            "description": "Storage at 85% capacity on primary database server",
            "severity": "medium",
            "status": "warning",
            "service_id": "svc-user-api",
            "team": "Infrastructure",
            "created_at": (datetime.now() - timedelta(days=1)).isoformat(),
            "started_at": (datetime.now() - timedelta(days=1, hours=2)).isoformat(),
            "assignee": "diana@example.com",
            "tags": ["infrastructure", "storage"],
        },
    ]


def create_port_payload(entity_type: str, entities: list):
    """
    Wrap entities in a Port-compatible payload structure.

    This mimics the structure that Ocean integrations expect from
    external systems.
    """
    return {
        "integration": SERVICE_NAME,
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "environment": ENVIRONMENT,
        "entity_type": entity_type,
        "entities": entities,
        "metadata": {
            "total_count": len(entities),
            "source": "mock-integration",
            "version": "1.0",
        },
    }


@app.route("/health", methods=["GET"])
def health():
    """Health check endpoint."""
    return jsonify({
        "status": "healthy",
        "service": SERVICE_NAME,
        "timestamp": datetime.utcnow().isoformat() + "Z",
    }), 200


@app.route("/api/services", methods=["GET"])
def get_services():
    """
    Endpoint 1: Return mock microservices/applications.

    This simulates an external system (e.g., an internal service registry)
    that provides application metadata. An Ocean integration would call
    this endpoint and send the data to Port as 'service' entities.

    Query parameters:
    - team: Filter by team name (optional)
    - status: Filter by status (optional)
    """
    team = request.args.get("team")
    status = request.args.get("status")

    services = generate_services()

    # Apply filters
    if team:
        services = [s for s in services if s.get("team", "").lower() == team.lower()]
    if status:
        services = [s for s in services if s.get("status", "").lower() == status.lower()]

    logger.info(f"Returning {len(services)} services")

    return jsonify(create_port_payload("service", services)), 200


@app.route("/api/incidents", methods=["GET"])
def get_incidents():
    """
    Endpoint 2: Return mock incidents/alerts.

    This simulates an external monitoring/alerting system that provides
    incident data. An Ocean integration would call this endpoint and send
    the data to Port as 'incident' entities, potentially relating them
    to services.

    Query parameters:
    - severity: Filter by severity (critical, high, medium, low)
    - status: Filter by status (investigating, resolved, warning)
    - service_id: Filter by related service
    """
    severity = request.args.get("severity")
    status = request.args.get("status")
    service_id = request.args.get("service_id")

    incidents = generate_incidents()

    # Apply filters
    if severity:
        incidents = [i for i in incidents if i.get("severity", "").lower() == severity.lower()]
    if status:
        incidents = [i for i in incidents if i.get("status", "").lower() == status.lower()]
    if service_id:
        incidents = [i for i in incidents if i.get("service_id", "") == service_id]

    logger.info(f"Returning {len(incidents)} incidents")

    return jsonify(create_port_payload("incident", incidents)), 200


@app.route("/api/docs", methods=["GET"])
def get_docs():
    """Documentation about available endpoints."""
    return jsonify({
        "service": SERVICE_NAME,
        "description": "Mock Port.io Integration Server for workshops",
        "endpoints": [
            {
                "path": "/health",
                "method": "GET",
                "description": "Health check endpoint",
            },
            {
                "path": "/api/services",
                "method": "GET",
                "description": "Get mock microservices/applications",
                "parameters": {
                    "team": "Filter by team name",
                    "status": "Filter by status (healthy, degraded)",
                },
            },
            {
                "path": "/api/incidents",
                "method": "GET",
                "description": "Get mock incidents/alerts",
                "parameters": {
                    "severity": "Filter by severity (critical, high, medium, low)",
                    "status": "Filter by status (investigating, resolved, warning)",
                    "service_id": "Filter by related service",
                },
            },
            {
                "path": "/api/docs",
                "method": "GET",
                "description": "This documentation",
            },
        ],
    }), 200


@app.before_request
def log_request():
    """Log incoming requests."""
    logger.info(f"{request.method} {request.path} from {request.remote_addr}")


@app.after_request
def log_response(response):
    """Log response status."""
    logger.info(f"Response: {response.status_code}")
    return response


@app.errorhandler(404)
def not_found(error):
    """Handle 404 errors."""
    return jsonify({
        "error": "Not found",
        "message": "The requested endpoint does not exist",
        "path": request.path,
    }), 404


@app.errorhandler(500)
def server_error(error):
    """Handle 500 errors."""
    logger.error(f"Server error: {error}")
    return jsonify({
        "error": "Internal server error",
        "message": str(error),
    }), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=PORT, debug=ENVIRONMENT == "development")
