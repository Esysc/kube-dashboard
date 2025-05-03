"""
This script is a Flask-based web application that integrates with Kubernetes to provide
real-time log streaming and pod information. It uses Flask-SocketIO for WebSocket communication
and the Kubernetes Python client for interacting with the Kubernetes API.

Modules:
    - flask: Provides the web framework.
    - flask_socketio: Enables WebSocket communication.
    - kubernetes: Interacts with the Kubernetes API.
    - threading: Allows concurrent log streaming.

Routes:
    - `/`: Renders the index.html template.
    - `/pods/<namespace>`: Returns a JSON list of pods and their containers
      in the specified namespace.

SocketIO Events:
    - `start`: Starts streaming logs for a specific pod and container
       in a namespace to a WebSocket room.
        - Data format: {'namespace': ..., 'pod': ..., 'container': ..., 'room': ...}
    - `stop`: Stops streaming logs and leaves the WebSocket room.
        - Data format: {'room': ...}

Functions:
    - `list_pods(namespace)`: Fetches and returns a list of pods
      and their containers in the given namespace.
    - `stream_logs(room, namespace, pod, container)`: Streams logs from a
      specific pod and container in a namespace
      to a WebSocket room.
    - `handle_start(data)`: Handles the `start` SocketIO event to initiate log streaming.
    - `handle_stop(data)`: Handles the `stop` SocketIO event to stop log streaming.

Usage:
    - Run the script to start the Flask application.
    - Access the web interface at `http://<host>:5000/`.
    - Use the `/pods/<namespace>` endpoint to retrieve pod information.
    - Use WebSocket events to start and stop log streaming.

Note:
    - Ensure that the Kubernetes configuration is properly set up before running the application.
    - Use `config.load_kube_config()` for local development or `config.load_incluster_config()`
      for in-cluster execution.
"""
import os
import threading
import time
from unittest.mock import MagicMock
from flask import Flask, render_template, jsonify, send_from_directory
from flask_socketio import SocketIO, join_room, leave_room
from kubernetes import client, config, watch
from kubernetes.client import V1Pod, V1ObjectMeta, V1PodSpec, V1Container

app = Flask(__name__)
socketio = SocketIO(app, cors_allowed_origins="*")

# Check if running in test mode
if os.getenv("TEST_MODE") == "true":
    # Mock Kubernetes client
    v1 = MagicMock()

    # Create mock pods
    pod_1 = V1Pod(
        metadata=V1ObjectMeta(name="pod-1"),
        spec=V1PodSpec(
            containers=[
                V1Container(name="container-1"),
                V1Container(name="container-2")
            ],
            init_containers=[]
        )
    )
    pod_2 = V1Pod(
        metadata=V1ObjectMeta(name="pod-2"),
        spec=V1PodSpec(
            containers=[
                V1Container(name="container-3")
            ],
            init_containers=[]
        )
    )

    # Mock the list_namespaced_pod method to return the mock pods
    v1.list_namespaced_pod = MagicMock(return_value=MagicMock(items=[pod_1, pod_2]))
else:
    # Load kube configuration for Kubernetes client
    config.load_kube_config()
    v1 = client.CoreV1Api()


@app.route('/')
def index():
    """
    Renders the main index page of the application.

    This function serves as the route handler for the root URL of the application.
    It renders and returns the 'index.html' template.

    Returns:
        Response: The rendered HTML content of the 'index.html' template.
    """
    return render_template('index.html')


@app.route('/assets/<path:filename>')
def serve_assets(filename):
    """
    Serves CSS and JavaScript files from their respective directories.

    This function determines the file type based on the file extension
    and serves the file from the appropriate directory.

    Args:
        filename (str): The name of the file to serve.

    Returns:
        Response: The requested file served from the appropriate directory.
    """
    if filename.endswith('.css'):
        return send_from_directory('templates/css', filename)
    if filename.endswith('.js'):
        return send_from_directory('templates/js', filename)
    return "File type not supported", 400


@app.route('/cluster-name')
def get_cluster_name():
    """
    Returns the name of the Kubernetes cluster.

    This function retrieves the cluster name from the Kubernetes configuration
    or a predefined value if the cluster name is not available.

    Returns:
        str: The name of the Kubernetes cluster.
    """
    if os.getenv("TEST_MODE") == "true":
        # Return a fake cluster name in test mode
        return "Mock Cluster"
    try:
        # Retrieve the cluster name from the Kubernetes configuration
        _, active_context = config.list_kube_config_contexts()
        cluster_name = active_context.get('context', {}).get('cluster', 'Unknown Cluster')
    except config.ConfigException as e:
        print(f"Error retrieving cluster name: {e}")
        cluster_name = "Unknown Cluster"

    return cluster_name


@app.route('/pods/<namespace>')
def list_pods(namespace):
    """
    List all pods in a given Kubernetes namespace along with their containers.
    This function retrieves all pods in the specified namespace using the Kubernetes API
    and returns a JSON response containing the pod names and their associated containers,
    including both regular containers and init containers.
    Args:
        namespace (str): The name of the Kubernetes namespace to list pods from.
    Returns:
        flask.Response: A JSON response containing a list of dictionaries, where each
        dictionary represents a pod with the following structure:
            - 'pod' (str): The name of the pod.
            - 'containers' (list of str): A list of container names in the pod.
    """

    pods = v1.list_namespaced_pod(namespace=namespace).items
    result = []
    for pod in pods:
        containers = []
        if pod.spec.containers:
            containers += [c.name for c in pod.spec.containers]
        if pod.spec.init_containers:
            containers += [c.name for c in pod.spec.init_containers]
        result.append({
            'pod': pod.metadata.name,
            'containers': containers
        })
    return jsonify(result)


def stream_logs(room, namespace, pod, container):
    """
    Stream logs from a specific container in a Kubernetes pod and emit them via a WebSocket.

    This function uses the Kubernetes Python client to stream logs from a specified container
    in a pod within a given namespace. The logs are emitted to a WebSocket room using `socketio`.

    Args:
        room (str): The WebSocket room to emit log messages to.
        namespace (str): The Kubernetes namespace where the pod is located.
        pod (str): The name of the pod to stream logs from.
        container (str): The name of the container within the pod to stream logs from.

    Emits:
        WebSocket Event: Emits a 'log' event with the following payload:
            - pod (str): The name of the pod.
            - container (str): The name of the container.
            - line (str): A single line of log output.
            - room (str): The WebSocket room the log is emitted to.

    Exceptions:
        Handles and prints any exceptions that occur during log streaming.

    Notes:
        - The function streams logs in real-time using the Kubernetes Watch API.
        - Only the last 100 lines of logs are fetched initially.
    """
    if os.getenv("TEST_MODE") == "true":
        for i in range(10):  # Emit 10 fake log lines
            socketio.emit('log', {
                'pod': pod,
                'container': container,
                'line': f"Fake log line {i} from {pod}/{container}",
                'room': room
            }, room=room)
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
            socketio.emit('log', {
                'pod': pod,
                'container': container,
                'line': line.strip(),
                'room': room
            }, room=room)

    except client.exceptions.ApiException as e:
        print(f"API error streaming logs for {pod}/{container}: {e}")


@socketio.on('start')
def handle_start(data):
    """
    Handles the initialization of a log streaming session for a
    specific container in a Kubernetes pod.

    Args:
        data (dict): A dictionary containing the following keys:
            - 'namespace' (str): The Kubernetes namespace of the pod.
            - 'pod' (str): The name of the pod.
            - 'container' (str): The name of the container within the pod.
            - 'room' (str): The identifier for the room to join for streaming logs.

    Behavior:
        - Extracts the namespace, pod, container, and room information from the input dictionary.
        - Joins the specified room for log streaming.
        - Starts a new daemon thread to stream logs from
          the specified container in the pod to the room.
    """
    namespace = data.get('namespace')
    pod = data.get('pod')
    container = data.get('container')
    room = data.get('room')
    join_room(room)
    threading.Thread(
        target=stream_logs,
        args=(room, namespace, pod, container),
        daemon=True
    ).start()


@socketio.on('stop')
def handle_stop(data):
    """
    Handles the termination of a log streaming session for a specific container in a Kubernetes pod.
    Args:
        data (dict): A dictionary containing the following key:
            - 'room' (str): The identifier for the room to leave.
    Behavior:
        - Extracts the room information from the input dictionary.
        - Leaves the specified room to stop receiving log messages.
    """
    room = data.get('room')
    leave_room(room)


if __name__ == '__main__':
    socketio.run(app, host="0.0.0.0", port=5000, debug=True)
