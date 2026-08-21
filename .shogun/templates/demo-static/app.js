const storageKey = "shogun-memory-garden";
const input = document.querySelector("#memory");
const list = document.querySelector("#memories");
const status = document.querySelector("#status");
const memories = () => JSON.parse(localStorage.getItem(storageKey) ?? "[]");
function render() {
  const items = memories();
  list.replaceChildren(...items.map((item) => { const entry = document.createElement("li"); entry.textContent = item; return entry; }));
  status.textContent = items.length ? `${items.length} browser memory${items.length === 1 ? "" : " memories"} recorded.` : "Nothing recorded in this browser yet.";
}
document.querySelector("#save").addEventListener("click", () => { const value = input.value.trim(); if (!value) return; localStorage.setItem(storageKey, JSON.stringify([...memories(), value])); input.value = ""; render(); });
input.addEventListener("keydown", (event) => { if (event.key === "Enter") document.querySelector("#save").click(); });
document.querySelector("#clear").addEventListener("click", () => { localStorage.removeItem(storageKey); render(); });
render();
