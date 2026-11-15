# Changelog

## 0.11.14

- **fix(mcp): answer `initialize`.** ChatGPT opens a session before it lists tools and abandons the
  connector when the method is refused. It was returning `404 Method not found`, which left plugin
  creation hanging and every tool panel in the app timing out with *"Get usage instructions timed out"*.
  A stateless server can answer harmlessly with the protocol version, capabilities and `serverInfo`.

## 0.11.13

- Honour the detail-panel setting: with the panel disabled, stop advertising `openai/outputTemplate` and
  stop offering the instruction tool, so the client is never handed a template it cannot render.
- Serve `200 text/event-stream` with a 15 s keep-alive on `GET /<slug>/mcp` instead of `405`. Clients that
  open an SSE stream read a refusal as a dead connector.

## 0.11.9

- Send three mascot cards in the instruction payload instead of the whole library (182 KB -> 45 KB).

## 0.11.8

- A tool result always carries a readable `text` content item; mirror `structuredContent` text when the
  content array would otherwise be empty.

## 0.11.7

- Cap the connector's long-poll hold at 2 s so the single-threaded listener cannot starve the instruction
  call.
