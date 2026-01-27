import gleam/option
import llmgleam/client
import llmgleam/types

pub fn new_client(provider: client.Provider, api_key: String) -> client.Client {
  client.new_client(provider, api_key)
}

