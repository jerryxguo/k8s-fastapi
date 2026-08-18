"""Gunicorn config for running the app under Uvicorn workers.

Most notably, `keepalive` is set just above the load balancer's idle
timeout to avoid 502s on connection races, and a rolling `max_requests`
jitter window recycles workers gradually.

"The load balancer" here is the AWS Load Balancer Controller-managed ALB
(via the Ingress resource) that fronts this service on EKS -- if that
ALB's idle timeout is ever changed, `keepalive` below needs to stay above it
or intermittent 502s will show up under load.
"""

import os

bind = "0.0.0.0:8080"
accesslog = "-"
errorlog = "-"
loglevel = "info"

# Default to 2 workers per pod (a reasonable baseline for a ~1 vCPU pod);
# override via WEB_CONCURRENCY if a pod is sized differently.
workers = int(os.environ.get("WEB_CONCURRENCY", "2"))
threads = 1  # app is async; extra threads per worker buy nothing here
worker_class = "uvicorn.workers.UvicornWorker"
preload_app = True

max_requests = 1000
max_requests_jitter = max_requests // 2

timeout = 30
# Must stay above the ALB/Ingress idle timeout (default 60s) or the LB can
# send a request down a connection gunicorn just closed -> intermittent 502.
keepalive = 61
backlog = 256
