// Клиент мира: говорит с игрой (или в будущем с общим сервером мира)
// по WebSocket. Протокол: {"id", "cmd", "args"} -> {"id", "ok", "result" | "error"}.
import WebSocket from "ws";

export class WorldClient {
  constructor(url, { timeoutMs = 10000 } = {}) {
    this.url = url;
    this.timeoutMs = timeoutMs;
    this.ws = null;
    this.connecting = null;
    this.nextId = 1;
    this.pending = new Map();
  }

  async connect() {
    if (this.ws?.readyState === WebSocket.OPEN) return;
    if (this.connecting) return this.connecting;
    this.connecting = new Promise((resolve, reject) => {
      const ws = new WebSocket(this.url, { maxPayload: 16 * 1024 * 1024 });
      ws.once("open", () => {
        this.ws = ws;
        resolve();
      });
      ws.once("error", (err) => {
        reject(
          new Error(
            `Cannot reach the game world at ${this.url} (${err.message}). ` +
              "Start the game (Godot, F5) and try again.",
          ),
        );
      });
      ws.on("message", (data) => this.#onMessage(data));
      ws.on("close", () => {
        if (this.ws === ws) this.ws = null;
        for (const { reject: fail } of this.pending.values()) fail(new Error("Connection to the game world closed"));
        this.pending.clear();
      });
    }).finally(() => {
      this.connecting = null;
    });
    return this.connecting;
  }

  #onMessage(data) {
    let msg;
    try {
      msg = JSON.parse(data.toString());
    } catch {
      return;
    }
    const waiter = this.pending.get(msg.id);
    if (!waiter) return;
    this.pending.delete(msg.id);
    clearTimeout(waiter.timer);
    if (msg.ok) waiter.resolve(msg.result);
    else waiter.reject(new Error(msg.error || "World rejected the request"));
  }

  async request(cmd, args = {}) {
    await this.connect();
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`The game world did not answer "${cmd}" in time`));
      }, this.timeoutMs);
      this.pending.set(id, { resolve, reject, timer });
      this.ws.send(JSON.stringify({ id, cmd, args }));
    });
  }

  close() {
    this.ws?.close();
  }
}
