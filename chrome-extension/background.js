const DEFAULT_MODEL = "gemini-1.5-flash";
const GEMINI_ENDPOINT =
  "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={apiKey}";

async function getSettings() {
  return new Promise((resolve) => {
    chrome.storage.sync.get(
      {
        apiKey: "",
        model: DEFAULT_MODEL,
      },
      (items) => resolve(items)
    );
  });
}

async function requestGemini({ apiKey, model, systemPrompt, userText }) {
  const endpoint = GEMINI_ENDPOINT.replace("{model}", model).replace("{apiKey}", apiKey);
  const response = await fetch(endpoint, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      contents: [
        {
          role: "user",
          parts: [
            { text: systemPrompt },
            { text: userText },
          ],
        },
      ],
      generationConfig: {
        temperature: 0.2,
      },
    }),
  });

  if (!response.ok) {
    const errText = await response.text();
    throw new Error(`Gemini API error: ${response.status} ${errText}`);
  }

  const data = await response.json();
  const message = data.candidates?.[0]?.content?.parts
    ?.map((part) => part.text)
    .join("")
    ?.trim();
  if (!message) {
    throw new Error("Empty response from Gemini API.");
  }

  return message;
}

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message?.type !== "translate" && message?.type !== "ask") {
    return;
  }

  (async () => {
    try {
      const settings = await getSettings();
      if (!settings.apiKey) {
        throw new Error("Missing Gemini API key. Please add it in extension options.");
      }

      const systemPrompt =
        message.type === "translate"
          ? "Translate the following English text to Chinese. Return only the translation."
          : "You are a helpful assistant. Answer the user's request in Chinese.";

      const result = await requestGemini({
        apiKey: settings.apiKey,
        model: settings.model || DEFAULT_MODEL,
        systemPrompt,
        userText: message.text,
      });

      sendResponse({ ok: true, result });
    } catch (error) {
      sendResponse({ ok: false, error: error.message || String(error) });
    }
  })();

  return true;
});
