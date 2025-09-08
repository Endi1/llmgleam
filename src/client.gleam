import gemini
import types

pub type Provider {
  Gemini
}

pub opaque type Client {
  GeminiClient(client: gemini.GeminiClientInternal)
}

pub fn new_client(provider: Provider, api_key: String) -> Client {
  case provider {
    Gemini -> GeminiClient(gemini.GeminiClientInternal(api_key:))
  }
}

pub fn completion(
  client: Client,
  model: String,
  messages: List(types.ChatMessage),
) -> Result(types.Completion, types.CompletionError) {
  case client {
    GeminiClient(c) -> gemini.generate_content(c, model, messages)
  }
}
