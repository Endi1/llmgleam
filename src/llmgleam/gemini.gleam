import gleam/dynamic/decode
import gleam/hackney
import gleam/http
import gleam/http/request
import gleam/json
import gleam/list
import gleam/option
import gleam/string
import llmgleam/types

pub type GeminiClientInternal {
  GeminiClientInternal(api_key: String)
}

pub type Content {
  Content(parts: List(Part), role: option.Option(types.Role))
}

pub type Part {
  TextPart(text: String)
}

pub type GenerateContentRequest {
  GenerateContentRequest(contents: List(Content))
}

pub type GenerateContentResponse {
  GenerateContentResponse(candidates: List(Candidate))
}

pub type Candidate {
  Candidate(content: Content, finish_reason: option.Option(String))
}

pub fn generate_content(
  client: GeminiClientInternal,
  model: String,
  messages: List(types.ChatMessage),
) -> Result(types.Completion, types.CompletionError) {
  let request_body = chat_messages_to_request(messages)
  let json_body = encode_request(request_body)

  // Create HTTP request
  let req =
    request.new()
    |> request.set_method(http.Post)
    |> request.set_host("generativelanguage.googleapis.com")
    |> request.set_path("/v1/models/" <> model <> ":generateContent")
    |> request.set_query([#("key", client.api_key)])
    |> request.set_header("content-type", "application/json")
    |> request.set_body(json.to_string(json_body))

  case hackney.send(req) {
    Ok(resp) -> {
      case resp.status {
        200 -> {
          case decode_response(resp.body) {
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

fn chat_messages_to_request(
  messages: List(types.ChatMessage),
) -> GenerateContentRequest {
  let contents =
    list.map(messages, fn(msg) {
      Content(parts: [TextPart(text: msg.content)], role: option.Some(msg.role))
    })
  GenerateContentRequest(contents:)
}

fn encode_part(part: Part) -> json.Json {
  case part {
    TextPart(text) -> json.object([#("text", json.string(text))])
  }
}

fn encode_content(content: Content) -> json.Json {
  let parts_json = json.array(from: content.parts, of: encode_part)
  case content.role {
    option.Some(role) ->
      json.object([
        #("parts", parts_json),
        #("role", json.string(role_to_str(role))),
      ])
    option.None ->
      json.object([#("parts", parts_json), #("role", json.string("user"))])
  }
}

fn role_to_str(role: types.Role) -> String {
  case role {
    types.System -> "system"
    types.User -> "user"
  }
}

fn encode_request(request: GenerateContentRequest) -> json.Json {
  json.object([#("contents", json.array(request.contents, encode_content))])
}

fn decode_response(
  json_string: String,
) -> Result(GenerateContentResponse, json.DecodeError) {
  let part_decoder = {
    use text <- decode.field("text", decode.string)
    decode.success(TextPart(text:))
  }

  let content_decoder = {
    use role <- decode.field("role", decode.string)
    use parts <- decode.field("parts", decode.list(part_decoder))
    decode.success(Content(role: str_to_role(role), parts:))
  }

  let candidate_decoder = {
    use content <- decode.field("content", content_decoder)
    use finish_reason <- decode.field("finishReason", decode.string)
    decode.success(Candidate(
      content:,
      finish_reason: option.Some(finish_reason),
    ))
  }

  let response_decoder = {
    use candidates <- decode.field("candidates", decode.list(candidate_decoder))
    decode.success(GenerateContentResponse(candidates:))
  }

  json.parse(json_string, response_decoder)
}

fn response_to_completion(
  response: GenerateContentResponse,
) -> Result(types.Completion, types.CompletionError) {
  case response.candidates {
    [candidate, ..] -> {
      case candidate.content.parts {
        [TextPart(text), ..] -> Ok(types.Completion(content: text))
        [] ->
          Error(types.ApiError("The gemini API returned incomplete candidates"))
      }
    }
    [] -> Error(types.ApiError("The gemini API returned incomplete candidates"))
  }
}

fn str_to_role(role_str: String) -> option.Option(types.Role) {
  case role_str {
    "user" -> option.Some(types.User)
    "system" -> option.Some(types.System)
    _ -> option.None
  }
}
