from app import app


def client():
    app.config["TESTING"] = True
    return app.test_client()


def test_home_returns_message():
    response = client().get("/")
    assert response.status_code == 200
    assert b"Internal GitLab Platform Demo" in response.data


def test_health_returns_ok():
    response = client().get("/health")
    assert response.status_code == 200
    assert response.get_json() == {"status": "ok"}
