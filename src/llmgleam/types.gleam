import gleam/option

pub type Role {
  User
  System
  Assistant
}

pub type ChatMessage {
  ChatMessage(content: String, role: Role)
}

pub type Completion {
  Completion(content: String)
}

pub type CompletionError {
  HttpError(String)
  JsonError(String)
  ApiError(String)
}

pub fn str_to_role(role_str: String) -> option.Option(Role) {
  case role_str {
    "user" -> option.Some(User)
    "system" -> option.Some(System)
    "assistant" -> option.Some(Assistant)
    _ -> option.None
  }
}
