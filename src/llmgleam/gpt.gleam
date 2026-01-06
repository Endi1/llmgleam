import gleam/dynamic/decode
import gleam/hackney
import gleam/http
import gleam/http/request
import gleam/json
import gleam/list
import gleam/option
import gleam/string
import llmgleam/types

pub type GPTClientInternal {
  GPTClientInternal(api_key: String)
}

pub type ChatCompletionRequest {
  ChatCompletionRequest(model: String, input: List(types.ChatMessage))
}

pub type Usage {
  Usage(prompt_tokens: Int, completion_tokens: Int, total_tokens: Int)
}

type ContentPart {
  ContentPart(text: String)
}

pub type ChatCompletion {
  ChatCompletion(
    id: String,
    output: List(types.ChatMessage),
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
  let base = [
    #("role", json.string(role_to_str(message.role))),
    #("content", json.string(message.content)),
  ]

  json.object(base)
}

fn encode_request(req: ChatCompletionRequest) -> json.Json {
  let req_json = [
    #("model", json.string(req.model)),
    #("input", json.array(req.input, encode_message)),
  ]
  json.object(req_json)
}

fn usage_decoder() -> decode.Decoder(Usage) {
  use prompt_tokens <- decode.field("input_tokens", decode.int)
  use completion_tokens <- decode.field("output_tokens", decode.int)
  use total_tokens <- decode.field("total_tokens", decode.int)
  decode.success(Usage(prompt_tokens:, completion_tokens:, total_tokens:))
}

fn content_part_decoder() -> decode.Decoder(ContentPart) {
  use text <- decode.field("text", decode.string)
  decode.success(ContentPart(text:))
}

fn chat_message_decoder() -> decode.Decoder(option.Option(types.ChatMessage)) {
  use choice_type <- decode.field("type", decode.string)
  case choice_type {
    "message" -> {
      use contents <- decode.field(
        "content",
        decode.list(content_part_decoder()),
      )
      let text =
        contents
        |> list.fold("", fn(acc, content) { string.append(acc, content.text) })

      use role_str <- decode.field("role", decode.string)

      let role = types.str_to_role(role_str)
      case role {
        option.Some(r) ->
          decode.success(option.Some(types.ChatMessage(role: r, content: text)))
        _ -> panic as "could not parse role"
      }
    }
    _ -> {
      decode.success(option.None)
    }
  }
}

fn chat_completion_decoder() -> decode.Decoder(ChatCompletion) {
  use id <- decode.field("id", decode.string)
  use output <- decode.field("output", decode.list(chat_message_decoder()))
  let filtered_output =
    output
    |> list.fold([], fn(acc, opt) {
      case opt {
        option.Some(value) -> [value, ..acc] |> list.reverse
        option.None -> acc
      }
    })
  use usage <- decode.field("usage", decode.optional(usage_decoder()))
  decode.success(ChatCompletion(id:, output: filtered_output, usage:))
}

fn response_to_completion(
  chat_completion: ChatCompletion,
) -> Result(types.Completion, types.CompletionError) {
  case chat_completion.output {
    [choice, ..] -> Ok(types.Completion(content: choice.content))
    [] -> Error(types.ApiError("The GPT API returned incomplete candidates"))
  }
}

pub fn generate_content(
  client: GPTClientInternal,
  model: String,
  messages: List(types.ChatMessage),
  _system_instruction: option.Option(String),
) -> Result(types.Completion, types.CompletionError) {
  let request_body = ChatCompletionRequest(model:, input: messages)
  let json_body = encode_request(request_body)

  // Create HTTP request
  let req =
    request.new()
    |> request.set_method(http.Post)
    |> request.set_host("api.openai.com")
    |> request.set_path("/v1/responses")
    |> request.set_header("content-type", "application/json")
    |> request.set_header("Authorization", "Bearer " <> client.api_key)
    |> request.set_body(json.to_string(json_body))

  case hackney.send(req) {
    Ok(resp) -> {
      case resp.status {
        200 -> {
          case json.parse(resp.body, chat_completion_decoder()) {
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
