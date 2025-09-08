pub type Role {
  User
  System
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
