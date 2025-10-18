import gleam/option
import llmgleam/gemini
import llmgleam/gpt
import llmgleam/types

pub type Provider {
  Gemini
  GPT
}

pub opaque type Client {
  GeminiClient(client: gemini.GeminiClientInternal)
  GPTClient(client: gpt.GPTClientInternal)
}

pub fn new_client(provider: Provider, api_key: String) -> Client {
  case provider {
    Gemini -> GeminiClient(gemini.GeminiClientInternal(api_key:))
    GPT -> GPTClient(gpt.GPTClientInternal(api_key:))
  }
}

pub fn completion(
  client: Client,
  model: String,
  messages: List(types.ChatMessage),
  system_instruction: option.Option(String),
) -> Result(types.Completion, types.CompletionError) {
  case client {
    GeminiClient(c) ->
      gemini.generate_content(c, model, messages, system_instruction)
    GPTClient(c) -> gpt.generate_content(c, model, messages, system_instruction)
  }
}
