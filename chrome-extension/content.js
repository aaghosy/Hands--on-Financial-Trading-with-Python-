const panelId = "pdf-translator-panel";
const spinnerId = "pdf-translator-spinner";

function getSelectionText() {
  const selection = window.getSelection();
  if (!selection || selection.rangeCount === 0) {
    return "";
  }
  return selection.toString().trim();
}

function getSelectionRect() {
  const selection = window.getSelection();
  if (!selection || selection.rangeCount === 0) {
    return null;
  }
  const range = selection.getRangeAt(0);
  const rect = range.getBoundingClientRect();
  if (!rect || rect.width === 0) {
    return null;
  }
  return rect;
}

function ensurePanel() {
  let panel = document.getElementById(panelId);
  if (panel) {
    return panel;
  }

  panel = document.createElement("div");
  panel.id = panelId;
  panel.innerHTML = `
    <div class="panel-header">
      <span>选中文本</span>
      <button class="panel-close" title="关闭">×</button>
    </div>
    <div class="panel-actions">
      <button class="panel-btn" data-action="translate">翻译成中文</button>
      <button class="panel-btn" data-action="ask">发给Gemini</button>
    </div>
    <div class="panel-body">
      <div class="panel-placeholder">点击按钮即可显示结果</div>
      <div class="panel-result"></div>
      <div class="panel-error"></div>
      <div id="${spinnerId}" class="panel-spinner" hidden>处理中...</div>
    </div>
  `;

  document.body.appendChild(panel);

  panel.querySelector(".panel-close").addEventListener("click", () => {
    panel.classList.remove("visible");
  });

  panel.querySelectorAll(".panel-btn").forEach((button) => {
    button.addEventListener("click", async (event) => {
      const action = event.currentTarget.dataset.action;
      const text = getSelectionText();
      if (!text) {
        showError(panel, "没有检测到选中文本。");
        return;
      }

      await handleRequest(panel, action, text);
    });
  });

  return panel;
}

function showPanelAt(rect) {
  const panel = ensurePanel();
  const top = window.scrollY + rect.bottom + 8;
  const left = window.scrollX + rect.left;

  panel.style.top = `${top}px`;
  panel.style.left = `${left}px`;
  panel.classList.add("visible");
}

function resetPanel(panel) {
  const placeholder = panel.querySelector(".panel-placeholder");
  const result = panel.querySelector(".panel-result");
  const error = panel.querySelector(".panel-error");
  const spinner = panel.querySelector(`#${spinnerId}`);

  placeholder.style.display = "block";
  result.textContent = "";
  error.textContent = "";
  spinner.hidden = true;
}

function showLoading(panel, isLoading) {
  const spinner = panel.querySelector(`#${spinnerId}`);
  spinner.hidden = !isLoading;
}

function showResult(panel, text) {
  const placeholder = panel.querySelector(".panel-placeholder");
  const result = panel.querySelector(".panel-result");
  const error = panel.querySelector(".panel-error");

  placeholder.style.display = "none";
  result.textContent = text;
  error.textContent = "";
}

function showError(panel, message) {
  const placeholder = panel.querySelector(".panel-placeholder");
  const result = panel.querySelector(".panel-result");
  const error = panel.querySelector(".panel-error");

  placeholder.style.display = "none";
  result.textContent = "";
  error.textContent = message;
}

async function handleRequest(panel, type, text) {
  resetPanel(panel);
  showLoading(panel, true);

  chrome.runtime.sendMessage({ type, text }, (response) => {
    showLoading(panel, false);
    if (!response) {
      showError(panel, "未收到扩展响应。");
      return;
    }
    if (!response.ok) {
      showError(panel, response.error || "请求失败。");
      return;
    }
    showResult(panel, response.result);
  });
}

function handleSelection() {
  const text = getSelectionText();
  if (!text) {
    return;
  }

  const rect = getSelectionRect();
  if (!rect) {
    return;
  }

  const panel = ensurePanel();
  resetPanel(panel);
  showPanelAt(rect);
}

window.addEventListener("mouseup", () => {
  setTimeout(handleSelection, 10);
});

window.addEventListener("keyup", (event) => {
  if (event.key === "Shift" || event.key === "Control") {
    setTimeout(handleSelection, 10);
  }
});
