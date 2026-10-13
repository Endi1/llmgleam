import gleam/option
import llmgleam/schema

pub type Role {
  User
  Assistant
}

pub type ChatMessage {
  ChatMessage(content: String, role: Role)
}

/// A model response containing text, tool calls, or both.
pub type Completion {
  Completion(
    content: option.Option(String),
    tool_calls: List(ToolCall),
    response_id: option.Option(String),
  )
}

/// A function tool that can be called by a model.
pub type Tool {
  Tool(
    name: String,
    description: String,
    parameters: schema.Parameters,
    strict: Bool,
  )
}

pub type ToolCall {
  ToolCall(id: String, call_id: String, name: String, arguments: String)
}

pub type ToolOutput {
  ToolOutput(call_id: String, output: String)
}

pub type CompletionError {
  HttpError(String)
  JsonError(String)
  ApiError(String)
}

pub fn str_to_role(role_str: String) -> option.Option(Role) {
  case role_str {
    "user" -> option.Some(User)
    "assistant" -> option.Some(Assistant)
    "model" -> option.Some(Assistant)
    _ -> option.None
  }
}
