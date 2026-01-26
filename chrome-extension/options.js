const apiKeyInput = document.getElementById("apiKey");
const modelInput = document.getElementById("model");
const statusEl = document.getElementById("status");
const saveButton = document.getElementById("save");

function showStatus(message) {
  statusEl.textContent = message;
  setTimeout(() => {
    statusEl.textContent = "";
  }, 2000);
}

function loadSettings() {
  chrome.storage.sync.get({ apiKey: "", model: "gemini-1.5-flash" }, (items) => {
    apiKeyInput.value = items.apiKey || "";
    modelInput.value = items.model || "gemini-1.5-flash";
  });
}

saveButton.addEventListener("click", () => {
  const apiKey = apiKeyInput.value.trim();
  const model = modelInput.value.trim() || "gemini-1.5-flash";

  chrome.storage.sync.set({ apiKey, model }, () => {
    showStatus("已保存。");
  });
});

loadSettings();
