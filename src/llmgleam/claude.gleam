import gleam/dynamic/decode
import gleam/hackney
import gleam/http
import gleam/http/request
import gleam/json
import gleam/option
import gleam/string
import llmgleam/types

pub type ClaudeClientInternal {
  ClaudeClientInternal(api_key: String)
}

pub type MessagesRequest {
  MessagesRequest(
    model: String,
    messages: List(types.ChatMessage),
    system: option.Option(String),
    max_tokens: Int,
  )
}

pub type Usage {
  Usage(input_tokens: Int, output_tokens: Int)
}

type ContentBlock {
  TextBlock(text: String)
}

type MessagesResponse {
  MessagesResponse(
    id: String,
    content: List(ContentBlock),
    role: String,
    usage: option.Option(Usage),
  )
}

pub fn role_to_str(role: types.Role) -> String {
  case role {
    types.User -> "user"
    types.Assistant -> "assistant"
  }
}

fn encode_message(message: types.ChatMessage) -> json.Json {
  json.object([
    #("role", json.string(role_to_str(message.role))),
    #("content", json.string(message.content)),
  ])
}

fn encode_request(req: MessagesRequest) -> json.Json {
  let base = [
    #("model", json.string(req.model)),
    #("messages", json.array(req.messages, encode_message)),
    #("max_tokens", json.int(req.max_tokens)),
  ]

  let with_system = case req.system {
    option.Some(s) -> [#("system", json.string(s)), ..base]
    option.None -> base
  }

  json.object(with_system)
}

fn usage_decoder() -> decode.Decoder(Usage) {
  use input_tokens <- decode.field("input_tokens", decode.int)
  use output_tokens <- decode.field("output_tokens", decode.int)
  decode.success(Usage(input_tokens:, output_tokens:))
}

fn content_block_decoder() -> decode.Decoder(ContentBlock) {
  use text <- decode.field("text", decode.string)
  decode.success(TextBlock(text:))
}

fn messages_response_decoder() -> decode.Decoder(MessagesResponse) {
  use id <- decode.field("id", decode.string)
  use content <- decode.field("content", decode.list(content_block_decoder()))
  use role <- decode.field("role", decode.string)
  use usage <- decode.field("usage", decode.optional(usage_decoder()))
  decode.success(MessagesResponse(id:, content:, role:, usage:))
}

fn response_to_completion(
  response: MessagesResponse,
) -> Result(types.Completion, types.CompletionError) {
  case response.content {
    [TextBlock(text), ..] -> Ok(types.Completion(content: text))
    [] ->
      Error(types.ApiError("The Claude API returned no content blocks"))
  }
}

pub fn generate_content(
  client: ClaudeClientInternal,
  model: String,
  messages: List(types.ChatMessage),
  system_instruction: option.Option(String),
) -> Result(types.Completion, types.CompletionError) {
  let request_body =
    MessagesRequest(
      model:,
      messages:,
      system: system_instruction,
      max_tokens: 8192,
    )
  let json_body = encode_request(request_body)

  // Create HTTP request
  let req =
    request.new()
    |> request.set_method(http.Post)
    |> request.set_host("api.anthropic.com")
    |> request.set_path("/v1/messages")
    |> request.set_header("content-type", "application/json")
    |> request.set_header("x-api-key", client.api_key)
    |> request.set_header("anthropic-version", "2023-06-01")
    |> request.set_body(json.to_string(json_body))

  case hackney.send(req) {
    Ok(resp) -> {
      case resp.status {
        200 -> {
          case json.parse(resp.body, messages_response_decoder()) {
            Ok(response) -> response_to_completion(response)
            Error(err) ->
              Error(types.JsonError(
                "Failed to decode response " <> string.inspect(err),
              ))
          }
        }
        _ ->
          Error(types.ApiError(
            "API returned status "
            <> string.inspect(resp.status)
            <> ": "
            <> resp.body,
          ))
      }
    }
    Error(err) ->
      Error(types.HttpError("HTTP request failed: " <> string.inspect(err)))
  }
}
