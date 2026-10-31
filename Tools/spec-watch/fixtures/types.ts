export type V2EventSessionCreated = {
  type: "session.created"
  data: { sessionID: string }
}
export type V2EventSessionGoalSet = {
  type: "session.goal.set"
  data: { sessionID: string }
}
export type V2EventRpc = {
  type: `rpc.${string}`
}

export type V2Event =
  | V2EventSessionCreated
  | V2EventSessionGoalSet
  | V2EventRpc

export type Other = { type: "x" }
