import gleam/list
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

pub opaque type Request {
  Request(
    messages: List(types.ChatMessage),
    client: Client,
    system_instruction: option.Option(String),
  )
}

pub fn with_message(request: Request, message: types.ChatMessage) -> Request {
  Request(
    messages: list.reverse([message, ..request.messages]),
    client: request.client,
    system_instruction: request.system_instruction,
  )
}

pub fn with_messages(
  request: Request,
  messages: List(types.ChatMessage),
) -> Request {
  Request(
    messages: list.append(request.messages, messages),
    client: request.client,
    system_instruction: request.system_instruction,
  )
}

pub fn new_client(provider: Provider, api_key: String) -> Client {
  case provider {
    Gemini -> GeminiClient(gemini.GeminiClientInternal(api_key:))
    GPT -> GPTClient(gpt.GPTClientInternal(api_key:))
  }
}

fn client_completion(
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

pub fn request(c: Client) -> Request {
  Request(messages: list.new(), client: c, system_instruction: option.None)
}

pub fn with_system_instruction(
  request: Request,
  system_instruction: String,
) -> Request {
  Request(
    messages: request.messages,
    client: request.client,
    system_instruction: option.Some(system_instruction),
  )
}

pub fn completion(
  request: Request,
  model: String,
) -> Result(types.Completion, types.CompletionError) {
  request.client |> client_completion(model, request.messages, request.system_instruction)
}
