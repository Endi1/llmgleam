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

pub type ClaudeClientInternal {
  ClaudeClientInternal(api_key: String)
}

pub type MessagesRequest {
  MessagesRequest(
    model: String,
    messages: List(types.ChatMessage),
    system: option.Option(String),
    max_tokens: Int,
    tools: List(types.Tool),
    tool_exchanges: List(#(types.Completion, List(types.ToolOutput))),
    pending_completion: option.Option(types.Completion),
    tool_outputs: List(types.ToolOutput),
  )
}

pub type Usage {
  Usage(input_tokens: Int, output_tokens: Int)
}

pub type ContentBlock {
  TextBlock(text: String)
  ToolUseBlock(call: types.ToolCall)
  IgnoredBlock
}

pub type MessagesResponse {
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

fn encode_tool(tool: types.Tool) -> json.Json {
  json.object([
    #("name", json.string(tool.name)),
    #("description", json.string(tool.description)),
    #("input_schema", schema.to_json(tool.parameters)),
    #("strict", json.bool(tool.strict)),
  ])
}

fn encode_tool_output(output: types.ToolOutput) -> json.Json {
  json.object([
    #("type", json.string("tool_result")),
    #("tool_use_id", json.string(output.call_id)),
    #("content", json.string(output.output)),
  ])
}

fn encode_tool_results(outputs: List(types.ToolOutput)) -> json.Json {
  json.object([
    #("role", json.string("user")),
    #("content", json.array(outputs, encode_tool_output)),
  ])
}

fn encode_tool_call(
  call: types.ToolCall,
) -> Result(json.Json, types.CompletionError) {
  case json.parse(call.arguments, json_value.decoder()) {
    Ok(input) ->
      Ok(
        json.object([
          #("type", json.string("tool_use")),
          #("id", json.string(call.id)),
          #("name", json.string(call.name)),
          #("input", json_value.to_json(input)),
        ]),
      )
    Error(error) ->
      Error(types.JsonError(
        "Failed to encode Claude tool arguments " <> string.inspect(error),
      ))
  }
}

fn encode_assistant_completion(
  completion: types.Completion,
) -> Result(json.Json, types.CompletionError) {
  use tool_calls <- result.try(list.try_map(
    completion.tool_calls,
    encode_tool_call,
  ))
  let text = case completion.content {
    option.Some(content) -> [
      json.object([
        #("type", json.string("text")),
        #("text", json.string(content)),
      ]),
    ]
    option.None -> []
  }

  Ok(
    json.object([
      #("role", json.string("assistant")),
      #("content", json.preprocessed_array(list.append(text, tool_calls))),
    ]),
  )
}

fn append_tool_results(
  messages: List(json.Json),
  outputs: List(types.ToolOutput),
) -> List(json.Json) {
  case outputs {
    [] -> messages
    outputs -> list.append(messages, [encode_tool_results(outputs)])
  }
}

@internal
pub fn encode_request(
  request: MessagesRequest,
) -> Result(json.Json, types.CompletionError) {
  use exchanges <- result.try(
    list.try_map(request.tool_exchanges, fn(exchange) {
      use assistant <- result.try(encode_assistant_completion(exchange.0))
      Ok(append_tool_results([assistant], exchange.1))
    }),
  )
  let messages =
    request.messages
    |> list.map(encode_message)
    |> list.append(list.flatten(exchanges))

  let messages_result = case request.pending_completion {
    option.Some(completion) -> {
      use assistant <- result.try(encode_assistant_completion(completion))
      Ok(append_tool_results(
        list.append(messages, [assistant]),
        request.tool_outputs,
      ))
    }
    option.None ->
      case request.tool_outputs {
        [] -> Ok(messages)
        [_, ..] ->
          Error(types.ApiError(
            "Claude tool outputs must follow client.continue_from",
          ))
      }
  }
  use messages <- result.try(messages_result)

  let base = [
    #("model", json.string(request.model)),
    #("messages", json.preprocessed_array(messages)),
    #("max_tokens", json.int(request.max_tokens)),
  ]
  let with_tools = case request.tools {
    [] -> base
    tools -> [#("tools", json.array(tools, encode_tool)), ..base]
  }
  let with_system = case request.system {
    option.Some(system) -> [#("system", json.string(system)), ..with_tools]
    option.None -> with_tools
  }

  Ok(json.object(with_system))
}

fn usage_decoder() -> decode.Decoder(Usage) {
  use input_tokens <- decode.field("input_tokens", decode.int)
  use output_tokens <- decode.field("output_tokens", decode.int)
  decode.success(Usage(input_tokens:, output_tokens:))
}

fn content_block_decoder() -> decode.Decoder(ContentBlock) {
  use block_type <- decode.field("type", decode.string)
  case block_type {
    "text" -> {
      use text <- decode.field("text", decode.string)
      decode.success(TextBlock(text:))
    }
    "tool_use" -> {
      use id <- decode.field("id", decode.string)
      use name <- decode.field("name", decode.string)
      use input <- decode.field("input", json_value.decoder())
      let arguments = input |> json_value.to_json |> json.to_string
      decode.success(
        ToolUseBlock(types.ToolCall(id:, call_id: id, name:, arguments:)),
      )
    }
    _ -> decode.success(IgnoredBlock)
  }
}

fn messages_response_decoder() -> decode.Decoder(MessagesResponse) {
  use id <- decode.field("id", decode.string)
  use content <- decode.field("content", decode.list(content_block_decoder()))
  use role <- decode.field("role", decode.string)
  use usage <- decode.field("usage", decode.optional(usage_decoder()))
  decode.success(MessagesResponse(id:, content:, role:, usage:))
}

@internal
pub fn decode_response(
  body: String,
) -> Result(MessagesResponse, json.DecodeError) {
  json.parse(body, messages_response_decoder())
}

@internal
pub fn response_to_completion(
  response: MessagesResponse,
) -> Result(types.Completion, types.CompletionError) {
  let #(texts, tool_calls) =
    response.content
    |> list.fold(#([], []), fn(acc, block) {
      case block {
        TextBlock(text) -> #([text, ..acc.0], acc.1)
        ToolUseBlock(call) -> #(acc.0, [call, ..acc.1])
        IgnoredBlock -> acc
      }
    })
  let content = case texts {
    [] -> option.None
    texts -> texts |> list.reverse |> string.join("") |> option.Some
  }
  let tool_calls = list.reverse(tool_calls)

  case content, tool_calls {
    option.None, [] ->
      Error(types.ApiError("The Claude API returned no content blocks"))
    _, _ ->
      Ok(types.Completion(
        content:,
        tool_calls:,
        response_id: option.Some(response.id),
      ))
  }
}

pub fn generate_content(
  client: ClaudeClientInternal,
  model: String,
  messages: List(types.ChatMessage),
  system_instruction: option.Option(String),
  tools: List(types.Tool),
  tool_exchanges: List(#(types.Completion, List(types.ToolOutput))),
  pending_completion: option.Option(types.Completion),
  tool_outputs: List(types.ToolOutput),
) -> Result(types.Completion, types.CompletionError) {
  let request_body =
    MessagesRequest(
      model:,
      messages:,
      system: system_instruction,
      max_tokens: 8192,
      tools:,
      tool_exchanges:,
      pending_completion:,
      tool_outputs:,
    )
  use json_body <- result.try(encode_request(request_body))

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
