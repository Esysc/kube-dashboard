""""
app.py

This module implements a Kubernetes Dashboard application using FastAPI and Socket.IO.
It provides a web interface to interact with Kubernetes clusters, view pod details,
and stream logs from containers in real-time.

Modules and Libraries:
- os: For environment variable access.
- argparse: For command-line argument parsing.
- threading: For running log streaming in separate threads.
- time: For simulating delays in test mode.
- asyncio: For asynchronous programming.
- unittest.mock: For mocking Kubernetes API in test mode.
- fastapi: For building the web application.
- fastapi.responses: For HTML and JSON responses.
- fastapi.staticfiles: For serving static files.
- kubernetes: For interacting with Kubernetes API.
- socketio: For WebSocket communication.
- jinja2: For rendering HTML templates.
- contextlib: For managing application lifespan.

Global Variables:
- MAIN_LOOP: Holds the main asyncio event loop for the application.

FastAPI Endpoints:
- `/`: Renders the main index page using Jinja2 templates.
- `/cluster-name`: Returns the name of the Kubernetes cluster.
- `/pods/{namespace}`: Lists all pods in a given Kubernetes namespace along with their containers.

Socket.IO Events:
- `connect`: Handles client connection events.
- `disconnect`: Handles client disconnection events.
- `start`: Initializes a log streaming session for a specific container in a Kubernetes pod.
- `stop`: Terminates a log streaming session for a specific container in a Kubernetes pod.

Functions:
- `lifespan(app: FastAPI)`: Manages the application lifespan and sets the global MAIN_LOOP.
- `stream_logs(sid, room, namespace, pod, container)`:
  Streams logs from a Kubernetes container and emits them via WebSocket.

Kubernetes Client Setup:
- In test mode (`TEST_MODE=true`), mock Kubernetes API responses are used.
- In real mode, the Kubernetes client is configured using the kubeconfig file.

Static Files:
- CSS and JS files are served from the `templates/css` and `templates/js` directories.

Command-Line Arguments:
- `--port`: Specifies the port to run the application on
  (default: 5000 or PORT environment variable).

Usage:
Run the application using the command:
    python app.py --port <port_number>
"""
import os
import argparse
import threading
import time
import asyncio
from contextlib import asynccontextmanager
from unittest.mock import MagicMock
from fastapi import FastAPI
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from kubernetes import client, config, watch
from kubernetes.client import V1Pod, V1ObjectMeta, V1PodSpec, V1Container
import socketio
from jinja2 import Environment, FileSystemLoader
# pylint: disable=unused-argument


class AppState:
    """
    Singleton class to manage application state.
    """
    _main_loop = None

    @classmethod
    def set_main_loop(cls, loop):
        """
        Set the main event loop for the application.
        :param loop: The asyncio event loop to set.
        """
        cls._main_loop = loop

    @classmethod
    def get_main_loop(cls):
        """
        Get the main event loop for the application.
        :return: The main event loop.
        """
        return cls._main_loop


# --- Lifespan context manager ---
@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Lifespan context manager to set up and tear down resources.
    """
    AppState.set_main_loop(asyncio.get_running_loop())
    yield
    # (optional: add shutdown code here)

# --- Setup FastAPI and Socket.IO ---
sio = socketio.AsyncServer(async_mode='asgi', cors_allowed_origins="*")
fastapi_app = FastAPI(lifespan=lifespan)
kube_dash = socketio.ASGIApp(sio, other_asgi_app=fastapi_app)

# --- Jinja2 for HTML templates ---
env = Environment(loader=FileSystemLoader('templates'))

# --- Mount static directories for CSS and JS ---
fastapi_app.mount("/assets/css", StaticFiles(directory="templates/css"), name="css")
fastapi_app.mount("/assets/js", StaticFiles(directory="templates/js"), name="js")

# --- Kubernetes client setup (mock/test mode or real) ---
if os.getenv("TEST_MODE") == "true":
    v1 = MagicMock()
    # Mock namespaces
    mock_namespaces = [
        V1ObjectMeta(name="default"),
        V1ObjectMeta(name="kube-system"),
        V1ObjectMeta(name="mock-namespace-1"),
        V1ObjectMeta(name="mock-namespace-2")
    ]
    v1.list_namespace = MagicMock(return_value=MagicMock(items=mock_namespaces))

    # Create mock pods
    pod_1 = V1Pod(
        metadata=V1ObjectMeta(name="pod-1"),
        spec=V1PodSpec(
            containers=[V1Container(name="container-1"), V1Container(name="container-2")],
            init_containers=[]
        )
    )
    pod_2 = V1Pod(
        metadata=V1ObjectMeta(name="pod-2"),
        spec=V1PodSpec(
            containers=[V1Container(name="container-3"), V1Container(name="container-4")],
            init_containers=[]
        )
    )
    pod_3 = V1Pod(
        metadata=V1ObjectMeta(name="pod-3"),
        spec=V1PodSpec(
            containers=[V1Container(name="container-5"), V1Container(name="container-6")],
            init_containers=[]
        )
    )
    pod_4 = V1Pod(
        metadata=V1ObjectMeta(name="pod-4"),
        spec=V1PodSpec(
            containers=[V1Container(name="container-7"), V1Container(name="container-8")],
            init_containers=[]
        )
    )
    v1.list_namespaced_pod = MagicMock(return_value=MagicMock(items=[pod_1, pod_2, pod_3, pod_4]))
else:
    config.load_kube_config()
    v1 = client.CoreV1Api()


# --- FastAPI Endpoints ---
@fastapi_app.get("/", response_class=HTMLResponse)
async def index():
    """
    Renders the main index page.
    """
    template = env.get_template("index.html")
    return HTMLResponse(template.render())


@fastapi_app.get("/cluster-name")
async def get_cluster_name():
    """
    Returns the name of the Kubernetes cluster.
    """
    if os.getenv("TEST_MODE") == "true":
        return "Mock Cluster"
    try:
        _, active_context = config.list_kube_config_contexts()
        cluster_name = active_context.get('context', {}).get('cluster', 'Unknown Cluster')
    except config.ConfigException as e:
        print(f"Error retrieving cluster name: {e}")
        cluster_name = "Unknown Cluster"
    return cluster_name


@fastapi_app.get("/namespaces")
async def list_namespaces():
    """
    List all available namespaces in the Kubernetes cluster.
    """
    if os.getenv("TEST_MODE") == "true":
        # Return mock namespaces in test mode
        return ["default", "kube-system", "mock-namespace-1", "mock-namespace-2"]

    try:
        namespaces = v1.list_namespace().items
        return [ns.metadata.name for ns in namespaces]
    except client.exceptions.ApiException as e:
        print(f"Error retrieving namespaces: {e}")
        return []


@fastapi_app.get("/pods/{namespace}")
async def list_pods(namespace: str):
    """
    List all pods in a given Kubernetes namespace along with their containers.
    """
    pods = v1.list_namespaced_pod(namespace=namespace).items
    result = []
    for pod in pods:
        containers = []
        if pod.spec.containers:
            containers += [c.name for c in pod.spec.containers]
        if pod.spec.init_containers:
            containers += [c.name for c in pod.spec.init_containers]
        result.append({'pod': pod.metadata.name, 'containers': containers})
    return result


# --- Socket.IO Events ---
def stream_logs(sid, room, namespace, pod, container):
    """
    Stream logs from a specific container in a Kubernetes pod and emit them via a WebSocket.
    Uses asyncio.run_coroutine_threadsafe to emit logs from a thread.
    """
    main_loop = AppState.get_main_loop()
    if os.getenv("TEST_MODE") == "true":
        for i in range(10):  # Emit 10 fake log lines
            asyncio.run_coroutine_threadsafe(
                sio.emit('log', {
                    'pod': pod,
                    'container': container,
                    'line': f"Fake log line {i} from {pod}/{container}",
                    'room': room
                }, room=room),
                main_loop
            )
            time.sleep(1)  # Simulate log streaming delay
        return

    w = watch.Watch()
    try:
        for line in w.stream(
            v1.read_namespaced_pod_log,
            name=pod,
            namespace=namespace,
            container=container,
            follow=True,
            tail_lines=100
        ):
            asyncio.run_coroutine_threadsafe(
                sio.emit('log', {
                    'pod': pod,
                    'container': container,
                    'line': line.strip(),
                    'room': room
                }, room=room),
                main_loop
            )
    except client.exceptions.ApiException as e:
        print(f"API error streaming logs for {pod}/{container}: {e}")


@sio.event
async def connect(sid, environ):
    """
    Handles client connection events.
    """
    print(f"Client connected: {sid}")


@sio.event
async def disconnect(sid):
    """
    Handles client disconnection events.
    """
    print(f"Client disconnected: {sid}")


@sio.event
async def start(sid, data):
    """
    Handles the initialization of a log streaming session for a specific container
    in a Kubernetes pod.
    """
    namespace = data.get('namespace')
    pod = data.get('pod')
    container = data.get('container')
    room = data.get('room')
    # Enter room from async context
    await sio.enter_room(sid, room)
    # Start log streaming in a thread
    threading.Thread(
        target=stream_logs,
        args=(sid, room, namespace, pod, container),
        daemon=True
    ).start()


@sio.event
async def stop(sid, data):
    """
    Handles the termination of a log streaming session for a specific container in a Kubernetes pod.
    """
    room = data.get('room')
    await sio.leave_room(sid, room)


# --- Run with Uvicorn ---
if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="Run the Kubernetes Dashboard application.")
    parser.add_argument(
        '--port',
        type=int,
        default=int(os.getenv("PORT", "5000")),
        help="Port to run the application on (default: 5000 or PORT env var)"
    )
    args = parser.parse_args()
    import uvicorn
    uvicorn.run(kube_dash, host="0.0.0.0", port=args.port)
