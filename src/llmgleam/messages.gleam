import llmgleam/types

pub fn user(content: String) -> types.ChatMessage {
  types.ChatMessage(content: content, role: types.User)
}

pub fn model(content: String) -> types.ChatMessage {
  types.ChatMessage(content: content, role: types.Assistant)
}
