import gleam/dynamic/decode
import gleam/hackney
import gleam/http
import gleam/http/request
import gleam/json
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import llmgleam/json_value
import llmgleam/schema
import llmgleam/types

pub type GeminiClientInternal {
  GeminiClientInternal(api_key: String)
}

pub type Content {
  Content(parts: List(Part), role: option.Option(types.Role))
}

pub type Part {
  TextPart(text: String)
  FunctionCallPart(call: types.ToolCall)
  IgnoredPart
}

pub type GenerateContentRequest {
  GenerateContentRequest(
    contents: List(Content),
    tools: List(types.Tool),
    tool_exchanges: List(#(types.Completion, List(types.ToolOutput))),
    pending_completion: option.Option(types.Completion),
    tool_outputs: List(types.ToolOutput),
  )
}

pub type GenerateContentResponse {
  GenerateContentResponse(candidates: List(Candidate))
}

pub type Candidate {
  Candidate(content: Content, finish_reason: option.Option(String))
}

pub fn role_to_str(role: types.Role) -> String {
  case role {
    types.User -> "user"
    types.Assistant -> "model"
  }
}

fn chat_messages_to_contents(messages: List(types.ChatMessage)) -> List(Content) {
  list.map(messages, fn(message) {
    Content(
      parts: [TextPart(text: message.content)],
      role: option.Some(message.role),
    )
  })
}

fn encode_function_call(
  call: types.ToolCall,
) -> Result(json.Json, types.CompletionError) {
  case json.parse(call.arguments, json_value.decoder()) {
    Ok(arguments) -> {
      let fields = [
        #("name", json.string(call.name)),
        #("args", json_value.to_json(arguments)),
      ]
      let fields = case call.id {
        "" -> fields
        id -> [#("id", json.string(id)), ..fields]
      }
      let part = [#("functionCall", json.object(fields))]
      let part = case call.thought_signature {
        option.Some(signature) -> [
          #("thoughtSignature", json.string(signature)),
          ..part
        ]
        option.None -> part
      }
      Ok(json.object(part))
    }
    Error(error) ->
      Error(types.JsonError(
        "Failed to encode Gemini tool arguments " <> string.inspect(error),
      ))
  }
}

fn encode_assistant_completion(
  completion: types.Completion,
) -> Result(json.Json, types.CompletionError) {
  use calls <- result.try(list.try_map(
    completion.tool_calls,
    encode_function_call,
  ))
  let text = case completion.content {
    option.Some(content) -> [
      json.object([#("text", json.string(content))]),
    ]
    option.None -> []
  }

  Ok(
    json.object([
      #("parts", json.preprocessed_array(list.append(text, calls))),
      #("role", json.string("model")),
    ]),
  )
}

fn output_name(
  output: types.ToolOutput,
  calls: List(types.ToolCall),
) -> Result(String, types.CompletionError) {
  case output.tool_name {
    option.Some(name) -> Ok(name)
    option.None ->
      case list.find(calls, fn(call) { call.call_id == output.call_id }) {
        Ok(call) -> Ok(call.name)
        Error(Nil) ->
          Error(types.ApiError(
            "Could not match the Gemini tool output to a function call",
          ))
      }
  }
}

fn encode_function_response(
  output: types.ToolOutput,
  calls: List(types.ToolCall),
) -> Result(json.Json, types.CompletionError) {
  use name <- result.try(output_name(output, calls))
  let value = case json.parse(output.output, json_value.decoder()) {
    Ok(value) -> json_value.to_json(value)
    Error(_) -> json.string(output.output)
  }
  let fields = [
    #("name", json.string(name)),
    #("response", json.object([#("result", value)])),
  ]
  let fields = case output.call_id {
    "" -> fields
    id -> [#("id", json.string(id)), ..fields]
  }
  Ok(json.object([#("functionResponse", json.object(fields))]))
}

fn encode_tool_results(
  completion: types.Completion,
  outputs: List(types.ToolOutput),
) -> Result(json.Json, types.CompletionError) {
  use responses <- result.try(
    list.try_map(outputs, fn(output) {
      encode_function_response(output, completion.tool_calls)
    }),
  )
  Ok(
    json.object([
      #("parts", json.preprocessed_array(responses)),
      #("role", json.string("user")),
    ]),
  )
}

fn append_tool_results(
  contents: List(json.Json),
  completion: types.Completion,
  outputs: List(types.ToolOutput),
) -> Result(List(json.Json), types.CompletionError) {
  case outputs {
    [] -> Ok(contents)
    outputs -> {
      use tool_results <- result.try(encode_tool_results(completion, outputs))
      Ok(list.append(contents, [tool_results]))
    }
  }
}

fn encode_content(content: Content) -> Result(json.Json, types.CompletionError) {
  use parts <- result.try(
    list.try_map(content.parts, fn(part) {
      case part {
        TextPart(text) -> Ok(json.object([#("text", json.string(text))]))
        FunctionCallPart(call) -> encode_function_call(call)
        IgnoredPart -> Ok(json.object([]))
      }
    }),
  )
  let fields = [#("parts", json.preprocessed_array(parts))]
  let fields = case content.role {
    option.Some(role) -> [#("role", json.string(role_to_str(role))), ..fields]
    option.None -> fields
  }
  Ok(json.object(fields))
}

fn encode_tool(tool: types.Tool) -> json.Json {
  json.object([
    #("name", json.string(tool.name)),
    #("description", json.string(tool.description)),
    #("parameters", schema.to_gemini_json(tool.parameters)),
  ])
}

@internal
pub fn encode_request(
  request: GenerateContentRequest,
  system_instruction: option.Option(String),
) -> Result(json.Json, types.CompletionError) {
  use base_contents <- result.try(list.try_map(request.contents, encode_content))
  use exchanges <- result.try(
    list.try_map(request.tool_exchanges, fn(exchange) {
      use assistant <- result.try(encode_assistant_completion(exchange.0))
      append_tool_results([assistant], exchange.0, exchange.1)
    }),
  )
  let contents = list.append(base_contents, list.flatten(exchanges))

  let contents_result = case request.pending_completion {
    option.Some(completion) -> {
      use assistant <- result.try(encode_assistant_completion(completion))
      append_tool_results(
        list.append(contents, [assistant]),
        completion,
        request.tool_outputs,
      )
    }
    option.None ->
      case request.tool_outputs {
        [] -> Ok(contents)
        [_, ..] ->
          Error(types.ApiError(
            "Gemini tool outputs must follow client.continue_from",
          ))
      }
  }
  use contents <- result.try(contents_result)

  let base = [
    #("contents", json.preprocessed_array(contents)),
  ]
  let with_tools = case request.tools {
    [] -> base
    tools -> [
      #(
        "tools",
        json.preprocessed_array([
          json.object([
            #("functionDeclarations", json.array(tools, encode_tool)),
          ]),
        ]),
      ),
      ..base
    ]
  }
  let with_system = case system_instruction {
    option.Some(instruction) -> [
      #(
        "systemInstruction",
        json.object([
          #(
            "parts",
            json.preprocessed_array([
              json.object([#("text", json.string(instruction))]),
            ]),
          ),
        ]),
      ),
      ..with_tools
    ]
    option.None -> with_tools
  }

  Ok(json.object(with_system))
}

fn text_part_decoder() -> decode.Decoder(Part) {
  use text <- decode.field("text", decode.string)
  decode.success(TextPart(text:))
}

fn function_call_part_decoder() -> decode.Decoder(Part) {
  use thought_signature <- decode.optional_field(
    "thoughtSignature",
    option.None,
    decode.string |> decode.map(option.Some),
  )
  use call <- decode.field("functionCall", {
    use id <- decode.optional_field("id", "", decode.string)
    use name <- decode.field("name", decode.string)
    use args <- decode.field("args", json_value.decoder())
    decode.success(types.ToolCall(
      id:,
      call_id: id,
      name:,
      arguments: args |> json_value.to_json |> json.to_string,
      thought_signature:,
    ))
  })
  decode.success(FunctionCallPart(call:))
}

fn part_decoder() -> decode.Decoder(Part) {
  decode.one_of(text_part_decoder(), or: [
    function_call_part_decoder(),
    decode.success(IgnoredPart),
  ])
}

fn content_decoder() -> decode.Decoder(Content) {
  use role <- decode.field("role", decode.string)
  use parts <- decode.field("parts", decode.list(part_decoder()))
  decode.success(Content(role: types.str_to_role(role), parts:))
}

fn candidate_decoder() -> decode.Decoder(Candidate) {
  use content <- decode.field("content", content_decoder())
  use finish_reason <- decode.optional_field(
    "finishReason",
    option.None,
    decode.string |> decode.map(option.Some),
  )
  decode.success(Candidate(content:, finish_reason:))
}

@internal
pub fn decode_response(
  body: String,
) -> Result(GenerateContentResponse, json.DecodeError) {
  let decoder = {
    use candidates <- decode.field(
      "candidates",
      decode.list(candidate_decoder()),
    )
    decode.success(GenerateContentResponse(candidates:))
  }
  json.parse(body, decoder)
}

@internal
pub fn response_to_completion(
  response: GenerateContentResponse,
) -> Result(types.Completion, types.CompletionError) {
  case response.candidates {
    [candidate, ..] -> {
      let #(texts, calls) =
        candidate.content.parts
        |> list.fold(#([], []), fn(acc, part) {
          case part {
            TextPart(text) -> #([text, ..acc.0], acc.1)
            FunctionCallPart(call) -> #(acc.0, [call, ..acc.1])
            IgnoredPart -> acc
          }
        })
      let content = case texts {
        [] -> option.None
        texts -> texts |> list.reverse |> string.join("") |> option.Some
      }
      let tool_calls = list.reverse(calls)
      case content, tool_calls {
        option.None, [] ->
          Error(types.ApiError("The Gemini API returned no content"))
        _, _ ->
          Ok(types.Completion(content:, tool_calls:, response_id: option.None))
      }
    }
    [] -> Error(types.ApiError("The Gemini API returned no candidates"))
  }
}

pub fn generate_content(
  client: GeminiClientInternal,
  model: String,
  messages: List(types.ChatMessage),
  system_instruction: option.Option(String),
  tools: List(types.Tool),
  tool_exchanges: List(#(types.Completion, List(types.ToolOutput))),
  pending_completion: option.Option(types.Completion),
  tool_outputs: List(types.ToolOutput),
) -> Result(types.Completion, types.CompletionError) {
  let request_body =
    GenerateContentRequest(
      contents: chat_messages_to_contents(messages),
      tools:,
      tool_exchanges:,
      pending_completion:,
      tool_outputs:,
    )
  use json_body <- result.try(encode_request(request_body, system_instruction))

  let req =
    request.new()
    |> request.set_method(http.Post)
    |> request.set_host("generativelanguage.googleapis.com")
    |> request.set_path("/v1beta/models/" <> model <> ":generateContent")
    |> request.set_header("content-type", "application/json")
    |> request.set_header("x-goog-api-key", client.api_key)
    |> request.set_body(json.to_string(json_body))

  case hackney.send(req) {
    Ok(resp) ->
      case resp.status {
        200 ->
          case decode_response(resp.body) {
            Ok(response) -> response_to_completion(response)
            Error(err) ->
              Error(types.JsonError(
                "Failed to decode response " <> string.inspect(err),
              ))
          }
        _ ->
          Error(types.ApiError(
            "API returned status "
            <> string.inspect(resp.status)
            <> ": "
            <> resp.body,
          ))
      }
    Error(err) ->
      Error(types.HttpError("HTTP request failed: " <> string.inspect(err)))
  }
}
