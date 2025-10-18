import gleam/option
import llmgleam/client
import llmgleam/types

pub fn new_client(provider: client.Provider, api_key: String) -> client.Client {
  client.new_client(provider, api_key)
}

pub fn completion(
  client: client.Client,
  model: String,
  messages: List(types.ChatMessage),
  system_instruction: option.Option(String)
) -> Result(types.Completion, types.CompletionError) {
  client.completion(client, model, messages, system_instruction)
}
