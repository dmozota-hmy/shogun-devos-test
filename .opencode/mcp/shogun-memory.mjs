#!/usr/bin/env node
import readline from "node:readline"
import fs from "node:fs"
import path from "node:path"

function loadConfig() {
  const configPath = process.env.TDAI_MEMORY_CONFIG || path.join(process.cwd(), ".shogun", "config", "memory.json")
  try {
    return JSON.parse(fs.readFileSync(configPath, "utf8"))
  } catch {
    return {
      memoryUrl: process.env.TDAI_MEMORY_URL || "http://127.0.0.1:8420",
      knowledgeUrl: process.env.TDAI_KNOWLEDGE_URL || "http://127.0.0.1:8424",
      serviceId: process.env.TDAI_SERVICE_ID || "default",
      userKey: process.env.TDAI_USER_KEY || "",
      gatewayKey: process.env.TDAI_MEMORY_API_KEY || "",
      teamId: process.env.TDAI_TEAM_ID || "",
      agentId: process.env.TDAI_AGENT_ID || "",
      taskId: process.env.TDAI_TASK_ID || "",
      sessionId: process.env.TDAI_SESSION_ID || `opencode-${process.cwd()}`
    }
  }
}

const config = loadConfig()
const coreUrl = (config.memoryUrl || "http://127.0.0.1:8420").replace(/\/$/, "")
const knowledgeUrl = (config.knowledgeUrl || "http://127.0.0.1:8424").replace(/\/$/, "")
const serviceId = config.serviceId || "default"
const userKey = config.userKey || ""
const gatewayKey = config.gatewayKey || ""
const teamId = config.teamId || ""
const agentId = config.agentId || ""
const taskId = config.taskId || ""
const sessionId = config.sessionId || `opencode-${process.cwd()}`

const tools = [
  { name: "tdai_memory_recall", description: "Search relevant project memory before planning.", inputSchema: { type: "object", properties: { query: { type: "string" }, limit: { type: "integer" } }, required: ["query"] } },
  { name: "tdai_memory_capture", description: "Persist a verified decision, pattern, bug fix, or learning.", inputSchema: { type: "object", properties: { content: { type: "string" }, category: { type: "string" } }, required: ["content"] } },
  { name: "tdai_conversation_search", description: "Search captured project conversations.", inputSchema: { type: "object", properties: { query: { type: "string" }, limit: { type: "integer" } }, required: ["query"] } },
  { name: "tdai_wiki_search", description: "Search a TencentDB Wiki asset.", inputSchema: { type: "object", properties: { wiki_id: { type: "string" }, query: { type: "string" }, limit: { type: "integer" } }, required: ["wiki_id", "query"] } },
  { name: "tdai_code_search", description: "Search symbols in a TencentDB CodeGraph asset.", inputSchema: { type: "object", properties: { code_graph_id: { type: "string" }, query: { type: "string" }, kind: { type: "string" }, limit: { type: "integer" } }, required: ["code_graph_id", "query"] } },
  { name: "tdai_code_impact", description: "Analyze the impact of changing a symbol.", inputSchema: { type: "object", properties: { code_graph_id: { type: "string" }, symbol: { type: "string" }, depth: { type: "integer" } }, required: ["code_graph_id", "symbol"] } }
]

const send = (message) => process.stdout.write(`${JSON.stringify(message)}\n`)
const response = (id, value) => send({ jsonrpc: "2.0", id, result: value })
const toolResult = (id, text, isError = false) => response(id, { content: [{ type: "text", text: typeof text === "string" ? text : JSON.stringify(text, null, 2) }], ...(isError ? { isError: true } : {}) })
const headers = () => ({ "Content-Type": "application/json", "x-tdai-service-id": serviceId, ...((gatewayKey || userKey) ? { Authorization: `Bearer ${gatewayKey || userKey}` } : {}) })

async function post(base, route, body) {
  const httpResponse = await fetch(`${base}${route}`, { method: "POST", headers: headers(), body: JSON.stringify(body) })
  const data = await httpResponse.json()
  if (!httpResponse.ok || (data.code !== undefined && data.code !== 0)) throw new Error(data.message || `TencentDB HTTP ${httpResponse.status}`)
  return data.data ?? data
}

async function verifyContext() {
  if (!teamId || !agentId || !taskId) throw new Error("Run .shogun/tools/Configure-ShogunMemory.ps1 first: Team, Agent and Task IDs are required.")
  if (!userKey) throw new Error("TencentDB user key is missing. Start the local hub first.")
  const auth = await post(coreUrl, "/v3/meta/auth/verify", { user_key: userKey })
  return auth.user?.user_id || auth.user_id
}

async function callTool(name, args) {
  const userId = await verifyContext()
  if (name === "tdai_memory_recall" || name === "tdai_conversation_search") return post(coreUrl, "/v3/conversation/search", { query: args.query, limit: args.limit || 10, team_id: teamId, agent_id: agentId, user_id: userId, task_id: taskId })
  if (name === "tdai_memory_capture") {
    const captured = await post(coreUrl, "/v3/conversation/add", { team_id: teamId, agent_id: agentId, user_id: userId, task_id: taskId, session_id: sessionId, messages: [{ role: "user", content: `[${args.category || "knowledge"}] ${args.content}` }] })
    const flushed = await post(coreUrl, "/session/end", { session_key: sessionId, user_id: userId })
    return { captured, flushed }
  }
  const routes = { tdai_wiki_search: "/wiki/search", tdai_code_search: "/code-graph/search", tdai_code_impact: "/code-graph/impact" }
  return post(knowledgeUrl, `/v3${routes[name]}`, { ...args, ...(name === "tdai_wiki_search" ? { team_id: teamId } : {}) })
}

readline.createInterface({ input: process.stdin, crlfDelay: Infinity }).on("line", async (line) => {
  if (!line.trim()) return
  let request
  try { request = JSON.parse(line) } catch { return }
  try {
    if (request.method === "initialize") response(request.id, { protocolVersion: "2024-11-05", capabilities: { tools: {} }, serverInfo: { name: "shogun-tencentdb-memory", version: "1.0.0" } })
    else if (request.method === "notifications/initialized") return
    else if (request.method === "tools/list") response(request.id, { tools })
    else if (request.method === "tools/call") toolResult(request.id, await callTool(request.params.name, request.params.arguments || {}))
    else if (request.id !== undefined) toolResult(request.id, `Unsupported MCP method: ${request.method}`, true)
  } catch (error) { if (request.id !== undefined) toolResult(request.id, error instanceof Error ? error.message : String(error), true) }
})
