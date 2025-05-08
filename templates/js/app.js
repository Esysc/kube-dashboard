const MAX_WINDOWS = 4;
const socket = io();
let availablePods = [];
let currentNamespace = '';
let windowCount = 0;
const logWindows = {};

// Fetch and display the cluster name
async function fetchClusterName() {
  try {
    const response = await fetch('/cluster-name');
    const data = await response.text();
    document.getElementById('clusterName').textContent = `Cluster: ${data}`;
  } catch (error) {
    console.error('Failed to fetch cluster name:', error);
    document.getElementById('clusterName').textContent = 'Cluster: Unknown';
  }
}

async function fetchNamespaces() {
  const namespaceSelect = document.getElementById('namespaceSelect');
  try {
    const response = await fetch('/namespaces');
    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`);
    }
    const namespaces = await response.json();
    console.log('Namespaces fetched:', namespaces); // Debugging line
    namespaceSelect.innerHTML = namespaces.map(ns => `<option value="${ns}">${ns}</option>`).join('');
  } catch (error) {
    console.error('Failed to fetch namespaces:', error);
    namespaceSelect.innerHTML = '<option value="" disabled>Error loading namespaces</option>';
  }
}

// Call these functions when the page loads
fetchClusterName();
fetchNamespaces();

// Handle form submission for loading pods
document.getElementById('namespaceForm').addEventListener('submit', async function (e) {
  e.preventDefault();
  const spinner = document.getElementById('spinner');
  const namespace = document.getElementById('namespaceSelect').value;
  if (!namespace) return;

  // Show the spinner
  spinner.style.display = 'inline-block';

  try {
    currentNamespace = namespace;
    const res = await fetch(`/pods/${encodeURIComponent(namespace)}`);
    availablePods = await res.json();

    // Enable the "Add Log Window" button if pods are available
    document.getElementById('addWindowBtn').disabled = availablePods.length === 0;

    // Clear existing log windows
    Object.keys(logWindows).forEach(wid => removeLogWindow(wid));
  } catch (error) {
    console.error('Failed to load pods:', error);
  } finally {
    // Hide the spinner
    spinner.style.display = 'none';
  }
});

document.getElementById('addWindowBtn').onclick = function() {
  if (windowCount >= MAX_WINDOWS || availablePods.length === 0) return;
  addLogWindow();
};

function isContainerSelected(pod, container, excludeWindowId) {
  return Object.keys(logWindows).some(id => {
    const win = logWindows[id];
    return win.pod === pod && win.container === container && id !== excludeWindowId;
  });
}

function removeLogWindow(windowId) {
  const win = logWindows[windowId];
  if (!win) return;

  // Stop the log stream for this window
  socket.emit('stop', { room: win.room });

  // Remove the window from the DOM
  const windowDiv = document.getElementById(windowId);
  if (windowDiv) {
    windowDiv.remove();
  }

  // Remove the window from the logWindows object
  delete logWindows[windowId];

  // Decrement the window count and update the Add Window button
  windowCount--;
  updateAddButton();
  // Update the selected containers
  // to ensure that the container options are updated in other windows

  updateSelectedContainers();
}

function addLogWindow() {
  const windowId = 'win_' + Date.now() + '_' + Math.floor(Math.random() * 10000);
  windowCount++;
  const windowDiv = document.createElement('div');
  windowDiv.className = 'log-window';
  windowDiv.id = windowId;

  const podSelect = document.createElement('select');
  const availablePodsWithContainers = availablePods.filter(p =>
    p.containers.some(c => !isContainerSelected(p.pod, c, windowId))
  );

  if (availablePodsWithContainers.length === 0) {
    alert('No available containers to add a new log window.');
    windowCount--;
    return;
  }

  podSelect.innerHTML = availablePodsWithContainers
    .map(p => `<option value="${p.pod}">${p.pod}</option>`)
    .join('');
  podSelect.className = 'pod-select';

  const containerSelect = document.createElement('select');
  const firstPod = availablePodsWithContainers[0];
  const availableContainers = firstPod.containers.filter(c =>
    !isContainerSelected(firstPod.pod, c, windowId)
  );

  containerSelect.innerHTML = availableContainers
    .map(c => `<option value="${c}">${c}</option>`)
    .join('');
  containerSelect.className = 'container-select';

  const searchInput = document.createElement('input');
  searchInput.type = 'text';
  searchInput.placeholder = 'Search logs...';

  const closeBtn = document.createElement('button');
  closeBtn.textContent = '×';
  closeBtn.className = 'close-btn';

  const logsDiv = document.createElement('div');
  logsDiv.className = 'logs';

  const headerDiv = document.createElement('div');
  headerDiv.className = 'window-header';
  headerDiv.appendChild(podSelect);
  headerDiv.appendChild(containerSelect);
  headerDiv.appendChild(searchInput);
  headerDiv.appendChild(closeBtn);

  windowDiv.appendChild(headerDiv);
  windowDiv.appendChild(logsDiv);
  document.getElementById('logWindows').appendChild(windowDiv);

  logWindows[windowId] = {
    pod: podSelect.value,
    container: containerSelect.value,
    logs: [],
    search: '',
    logsDiv: logsDiv,
    searchInput: searchInput,
    podSelect: podSelect,
    containerSelect: containerSelect,
    room: windowId
  };

  socket.emit('start', {
    namespace: currentNamespace,
    pod: podSelect.value,
    container: containerSelect.value,
    room: windowId
  });

  // Update container dropdown when pod is changed
  podSelect.addEventListener('change', function () {
    const win = logWindows[windowId];
    const newPod = podSelect.value;
    const podObj = availablePods.find(p => p.pod === newPod);

    if (!podObj) return;

    const availableContainers = podObj.containers.filter(c =>
      !isContainerSelected(newPod, c, windowId)
    );

    if (availableContainers.length > 0) {
      containerSelect.innerHTML = availableContainers
        .map(c => `<option value="${c}">${c}</option>`)
        .join('');
      win.container = availableContainers[0]; // Automatically select the first container
      // Force the container select to update its value.
      // Pods may contain containers having same name.
      // We need to ensure the selected container is refreshed.
      containerSelect.value = win.container;
    } else {
      containerSelect.innerHTML = '<option value="" disabled>No containers available</option>';
      win.container = null;
    }

    win.pod = newPod;

    // Restart log streaming with the new pod and container
    if (win.container) {
      containerChanged(win);
      containerSelect.dispatchEvent(new Event('change'));
    }
  });

  containerSelect.addEventListener('change', function () {
    const win = logWindows[windowId];
    if (containerSelect.options[containerSelect.selectedIndex].disabled) return;
    win.container = containerSelect.value;
    containerChanged(win);
    updateSelectedContainers();
  });

  searchInput.addEventListener('input', function () {
    logWindows[windowId].search = searchInput.value.toLowerCase();
    renderLogs(windowId);
  });

  closeBtn.addEventListener('click', function () {
    removeLogWindow(windowId);
  });

  updateSelectedContainers();
  updateAddButton();
}

function containerChanged(win) {
  win.logs = [];
  win.logsDiv.innerHTML = '';
  socket.emit('stop', { room: win.room });
  socket.emit('start', {
    namespace: currentNamespace,
    pod: win.pod,
    container: win.container,
    room: win.room
  });
}

function updateSelectedContainers() {
  const selectedContainers = {};
  Object.values(logWindows).forEach(win => {
    if (!selectedContainers[win.pod]) {
      selectedContainers[win.pod] = new Set();
    }
    selectedContainers[win.pod].add(win.container);
  });

  Object.values(logWindows).forEach(win => {
    const podName = win.pod;
    const podObj = availablePods.find(p => p.pod === podName);
    if (!podObj) return;

    const currentSelection = win.container;
    const currentSelectionIsValid = podObj.containers.includes(currentSelection);

    const options = podObj.containers
      .filter(c => !selectedContainers[podName] || !selectedContainers[podName].has(c) || c === currentSelection)
      .map(c => `<option value="${c}" ${c === currentSelection ? 'selected' : ''}>${c}</option>`)
      .join('');

    win.containerSelect.innerHTML = options;

    if (!currentSelectionIsValid && win.containerSelect.options.length > 0) {
      win.container = win.containerSelect.options[0].value;
      win.containerSelect.value = win.container;
      if (win.container !== currentSelection) {
        containerChanged(win);
      }
    }
  });
}

function updateAddButton() {
  document.getElementById('addWindowBtn').disabled = (windowCount >= MAX_WINDOWS) || (availablePods.length === 0);
}

function renderLogs(windowId) {
  const win = logWindows[windowId];
  if (!win) return;
  const logsDiv = win.logsDiv;
  const search = win.search;
  logsDiv.innerHTML = '';
  win.logs.forEach(log => {
    if (!search || log.line.toLowerCase().includes(search)) {
      const div = document.createElement('div');
      div.className = 'log-line';
      div.innerHTML = `<span class="pod-label">[${log.pod}]</span>` +
                      `<span class="container-label">[${log.container}]</span>` +
                      `<span class="timestamp">${log.time}</span>` +
                      log.line.replace(/</g, '&lt;').replace(/>/g, '&gt;');
      logsDiv.appendChild(div);
    }
  });
  logsDiv.scrollTop = 0;
}

function getTime() {
  const now = new Date();
  return now.toLocaleTimeString();
}

socket.on('log', data => {
  const windowId = Object.keys(logWindows).find(id => logWindows[id].room === data.room);
  if (!windowId) return;

  const win = logWindows[windowId];
  // Check if the log belongs to the current pod and container
  if (data.pod === win.pod && data.container === win.container) {
    win.logs.unshift({
      pod: data.pod,
      container: data.container,
      line: data.line,
      time: getTime()
    });

    // Render the log immediately if there's no search filter
    if (!win.search) {
      const div = document.createElement('div');
      div.className = 'log-line';
      div.innerHTML = `<span class="pod-label">[${data.pod}]</span>` +
                      `<span class="container-label">[${data.container}]</span>` +
                      `<span class="timestamp">${getTime()}</span>` +
                      data.line.replace(/</g, '&lt;').replace(/>/g, '&gt;');
      win.logsDiv.insertBefore(div, win.logsDiv.firstChild);
      win.logsDiv.scrollTop = 0;
    } else {
      renderLogs(windowId);
    }
  }
});
