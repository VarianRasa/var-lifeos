const API_BASE = 'http://127.0.0.1:18420/v1';
const TOKEN = 'var-local-token';

document.addEventListener('DOMContentLoaded', async () => {
  const boardSelect = document.getElementById('boardSelect');
  const saveBtn = document.getElementById('saveBtn');
  const statusDiv = document.getElementById('status');

  try {
    const res = await fetch(`${API_BASE}/boards`, {
      headers: { 'Authorization': `Bearer ${TOKEN}` }
    });
    if (!res.ok) throw new Error('Unauthorized or app not running');
    const data = await res.json();

    boardSelect.innerHTML = '<option value="">Select Board *</option>';
    data.boards.forEach(b => {
      const opt = document.createElement('option');
      opt.value = b.boardId;
      opt.textContent = b.boardTitle;
      boardSelect.appendChild(opt);
    });
  } catch (err) {
    statusDiv.textContent = 'Error: Cannot connect to Var app. Open app first.';
    return;
  }

  boardSelect.addEventListener('change', () => {
    saveBtn.disabled = !boardSelect.value;
  });

  saveBtn.addEventListener('click', async () => {
    saveBtn.disabled = true;
    statusDiv.textContent = 'Clipping...';

    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    const payload = {
      mode: document.getElementById('clipMode').value,
      urls: [tab.url],
      text: tab.title,
      boardId: boardSelect.value,
      workspaceId: 'default',
    };

    try {
      const res = await fetch(`${API_BASE}/capture`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${TOKEN}`
        },
        body: JSON.stringify(payload)
      });

      if (res.ok) {
        statusDiv.textContent = 'Clipped successfully!';
        setTimeout(() => window.close(), 1000);
      } else {
        throw new Error('Save failed');
      }
    } catch (err) {
      statusDiv.textContent = 'Failed to clip: ' + err.message;
      saveBtn.disabled = false;
    }
  });
});
