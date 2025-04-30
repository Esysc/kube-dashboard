# Kubernetes Multi-Log Dashboard

A web-based dashboard for monitoring logs from multiple Kubernetes pods and containers in real-time. This tool allows you to open up to 4 separate log windows, each streaming logs from a specific pod and container, with proper isolation between streams.

## Features

- **Real-Time Log Streaming**: View logs from Kubernetes pods and containers in real-time.
- **Multiple Log Windows**: Open up to 4 log windows simultaneously, each streaming logs from a different container.
- **Namespace Filtering**: Load pods from a specific namespace.
- **Search Logs**: Filter logs in each window using a search input.
- **Dynamic Container Selection**: Prevents selecting the same container in multiple windows.
- **Responsive Design**: Works well on both desktop and mobile devices.

## Prerequisites

- **Kubernetes Cluster**: Ensure you have access to a running Kubernetes cluster.
- **Python 3.8+**: Required to run the Flask backend.
- **kubectl**: Ensure `kubectl` is configured to access your Kubernetes cluster.

## Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/esysc/kube-dashboard.git
   cd kube-dashboard
   ```
2. Install Python dependencies:
   ```
   pip install -r requirements.txt
   ```
3. Start the Flask server
   ```
   python app.py
   ```

```markdown
# Kubernetes Multi-Log Dashboard

A web-based dashboard for monitoring logs from multiple Kubernetes pods and containers in real-time. This tool allows you to open up to 4 separate log windows, each streaming logs from a specific pod and container, with proper isolation between streams.

## Features

- **Real-Time Log Streaming**: View logs from Kubernetes pods and containers in real-time.
- **Multiple Log Windows**: Open up to 4 log windows simultaneously, each streaming logs from a different container.
- **Namespace Filtering**: Load pods from a specific namespace.
- **Search Logs**: Filter logs in each window using a search input.
- **Dynamic Container Selection**: Prevents selecting the same container in multiple windows.
- **Responsive Design**: Works well on both desktop and mobile devices.

## Prerequisites

- **Kubernetes Cluster**: Ensure you have access to a running Kubernetes cluster.
- **Python 3.8+**: Required to run the Flask backend.
- **Node.js**: Required for Socket.IO integration.
- **kubectl**: Ensure `kubectl` is configured to access your Kubernetes cluster.

## Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/esysc/kube-dashboard.git
   cd kube-dashboard
   ```

2. Install Python dependencies:
   ```bash
   pip install -r requirements.txt
   ```

3. Start the Flask server:
   ```bash
   python app.py
   ```

4. Open your browser and navigate to:
   ```
   http://localhost:5000
   ```

## Usage

1. Enter the desired Kubernetes namespace in the input field and click **Load Pods**.
2. Click **Add Log Window** to open a new log window.
3. Select a pod and container from the dropdown menus in the log window.
4. View real-time logs for the selected container.
5. Use the search input to filter logs by keywords.
6. Close a log window by clicking the **×** button.

### Notes

- A maximum of 4 log windows can be opened at a time.
- Containers already selected in one window will not appear as options in other windows.

## Contributing

Contributions are welcome! Please follow these steps:

1. Fork the repository.
2. Create a new branch for your feature or bugfix.
3. Commit your changes and push the branch.
4. Open a pull request.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [Flask](https://flask.palletsprojects.com/) for the backend framework.
- [Socket.IO](https://socket.io/) for real-time communication.
- Kubernetes for providing the infrastructure for container orchestration.
