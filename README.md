# Kubernetes Multi-Log Dashboard

A web-based dashboard for monitoring logs from multiple Kubernetes pods and containers in real-time. This tool allows you to open up to 4 separate log windows, each streaming logs from a specific pod and container, with proper isolation between streams.

## Features

- **Real-Time Log Streaming**: View logs from Kubernetes pods and containers in real-time.
- **Multiple Log Windows**: Open up to 4 log windows simultaneously, each streaming logs from a different container.
- **Namespace Filtering**: Load pods from a specific namespace.
- **Search Logs**: Filter logs in each window using a search input.
- **Dynamic Container Selection**: Prevents selecting the same container in multiple windows.
- **Responsive Design**: Works well on both desktop and mobile devices.
- **Cluster Name Display**: Displays the Kubernetes cluster name in the dashboard header.
- **Spinner for Loading**: A spinner is displayed while loading pods.

## Prerequisites

- **Kubernetes Cluster**: Ensure you have access to a running Kubernetes cluster.
- **Python 3.8+**: Required to run the FastAPI backend.
- **kubectl**: Ensure `kubectl` is configured to access your Kubernetes cluster. Alternatively, for testing purposes, you can set `TEST_MODE=true` to use mock data.
- **Docker**: Required if you want to run the application in a container.

## Installation

### 1. Clone the Repository
```bash
git clone https://github.com/esysc/kube-dashboard.git
cd kube-dashboard
```

### 2. Install Python Dependencies
```bash
pip install -r requirements.txt
```

### 3. Start the FastAPI Server
```bash
python app.py --port 5000
```
The port argument is optional, defaults to `5000`, and can also be passed as an environment variable:
```bash
export PORT=5000
```

### 4. Open Your Browser
Navigate to:
```
http://localhost:5000
```

---

## Running with Docker

You can also run the application using Docker:

### 1. Build the Docker Image
```bash
docker build -t kube-dashboard .
```

### 2. Run the Docker Container
```bash
docker run -p 5000:5000 -e PORT=5000 kube-dashboard
```
or if you want to use mock data:
```bash
docker run -p 5000:5000 -e PORT=5000 -e TEST_MODE=true kube-dashboard
```
### 3. Access the Application
Open your browser and navigate to:
```
http://localhost:5000
```

---

## Testing

### 1. Testing with Mock Data (`TEST_MODE=true`)

To test the application without connecting to a real Kubernetes cluster, you can enable `TEST_MODE`:

```bash
export TEST_MODE=true
python app.py --port 5000
```

In this mode:
- Mock Kubernetes pods and containers are used.
- The application simulates log streaming for testing purposes.

### 2. Manual Testing

- Start the FastAPI server:
  ```bash
  python app.py --port 5000
  ```
- Open your browser and navigate to `http://localhost:5000`.
- Verify that you can:
  - Load pods from a Kubernetes namespace.
  - Open up to 4 log windows.
  - Stream logs in real-time for selected pods and containers.
  - Filter logs using the search input.
  - Dynamically select containers without duplication.

### 3. Integration Testing

- Ensure `kubectl` is configured correctly and can access your Kubernetes cluster.
- Test the interaction between the FastAPI backend and the Kubernetes API by loading pods and streaming logs.

### 4. Cross-Browser Testing

- Test the dashboard on multiple browsers (e.g., Chrome, Firefox, Edge) to ensure compatibility.

### 5. Responsive Design Testing

- Verify that the dashboard works well on both desktop and mobile devices.

### 6. Error Handling

- Test scenarios where the Kubernetes cluster is unreachable or invalid inputs are provided to ensure proper error messages are displayed.

---

## Usage

1. Enter the desired Kubernetes namespace in the input field and click **Load Pods**.
2. Click **Add Log Window** to open a new log window.
3. Select a pod and container from the dropdown menus in the log window.
4. View real-time logs for the selected container.
5. Use the search input to filter logs by keywords.
6. Close a log window by clicking the **×** button.

---

## Development Notes

### Migration from Flask to FastAPI

The application was migrated from Flask to FastAPI for better performance and asynchronous support. Key changes include:
- **FastAPI Lifespan**: Used to manage application lifecycle and resources.
- **Socket.IO Integration**: The `socketio.ASGIApp` is used to integrate Socket.IO with FastAPI.
- **Static Files**: Static files (CSS and JS) are served using `fastapi.staticfiles.StaticFiles`.

### Mock Testing with `TEST_MODE=true`

When `TEST_MODE=true` is set as an environment variable:
- Mock Kubernetes pods and containers are created using `unittest.mock`.
- The application simulates log streaming for testing purposes.

---

## Contributing

Contributions are welcome! Please follow these steps:

1. Fork the repository.
2. Create a new branch for your feature or bugfix.
3. Commit your changes and push the branch.
4. Open a pull request.

---

## Acknowledgments

- [FastAPI](https://fastapi.tiangolo.com/) for the backend framework.
- [Socket.IO](https://socket.io/) for real-time communication.
- Kubernetes for providing the infrastructure for container orchestration.
