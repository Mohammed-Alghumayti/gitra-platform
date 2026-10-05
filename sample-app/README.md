# Internal Demo App

A minimal Flask app used to demonstrate the Gitra CI/CD pipeline.

| Route | Response |
|---|---|
| `/` | `Internal GitLab Platform Demo` |
| `/health` | `{"status": "ok"}` |

## Pipeline (`.gitlab-ci.yml`)

| Stage | Job | What it does |
|---|---|---|
| test | `test` | Installs requirements and runs `pytest` |
| build | `build` | Builds the Docker image, tagged with the commit SHA |
| deploy | `deploy_staging` | Runs the image on the runner VM at port `5000` (default branch only) |

## Run locally

```bash
pip install -r requirements.txt
pytest -v
python app.py            # http://localhost:5000
```

Or with Docker:

```bash
docker build -t internal-demo-app .
docker run --rm -p 5000:5000 internal-demo-app
```

## Use it in GitLab

Create a project in GitLab and push the contents of this folder to it as the
project root. The pipeline runs on the platform's registered runner.
