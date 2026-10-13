import gleam/dynamic/decode
import gleam/hackney
import gleam/http
import gleam/http/request
import gleam/json
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import llmgleam/schema
import llmgleam/types

pub type GPTClientInternal {
  GPTClientInternal(api_key: String)
}

pub type ChatCompletionRequest {
  ChatCompletionRequest(
    model: String,
    input: List(types.ChatMessage),
    tools: List(types.Tool),
    tool_outputs: List(types.ToolOutput),
    previous_response_id: option.Option(String),
  )
}

pub type Usage {
  Usage(prompt_tokens: Int, completion_tokens: Int, total_tokens: Int)
}

type ContentPart {
  ContentPart(text: String)
}

type OutputItem {
  MessageOutput(types.ChatMessage)
  FunctionCallOutput(types.ToolCall)
  IgnoredOutput
}

pub type ChatCompletion {
  ChatCompletion(
    id: String,
    output: List(types.ChatMessage),
    tool_calls: List(types.ToolCall),
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
    #("type", json.string("function")),
    #("name", json.string(tool.name)),
    #("description", json.string(tool.description)),
    #("parameters", schema.to_json(tool.parameters)),
    #("strict", json.bool(tool.strict)),
  ])
}

fn encode_tool_output(output: types.ToolOutput) -> json.Json {
  json.object([
    #("type", json.string("function_call_output")),
    #("call_id", json.string(output.call_id)),
    #("output", json.string(output.output)),
  ])
}

@internal
pub fn encode_request(
  req: ChatCompletionRequest,
  system_instruction: option.Option(String),
) -> json.Json {
  let input =
    list.append(
      list.map(req.input, encode_message),
      list.map(req.tool_outputs, encode_tool_output),
    )
  let base = [
    #("model", json.string(req.model)),
    #("input", json.preprocessed_array(input)),
  ]
  let with_tools = case req.tools {
    [] -> base
    tools -> [#("tools", json.array(tools, encode_tool)), ..base]
  }
  let with_previous_response = case req.previous_response_id {
    option.Some(id) -> [
      #("previous_response_id", json.string(id)),
      ..with_tools
    ]
    option.None -> with_tools
  }
  let with_system = case system_instruction {
    option.Some(i) -> [
      #("instructions", json.string(i)),
      ..with_previous_response
    ]
    option.None -> with_previous_response
  }
  json.object(with_system)
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

fn output_item_decoder() -> decode.Decoder(OutputItem) {
  use item_type <- decode.field("type", decode.string)
  case item_type {
    "message" -> {
      use contents <- decode.field(
        "content",
        decode.list(content_part_decoder()),
      )
      let text =
        contents
        |> list.map(fn(content) { content.text })
        |> string.join("")

      use role_str <- decode.field("role", decode.string)
      case types.str_to_role(role_str) {
        option.Some(role) ->
          decode.success(MessageOutput(types.ChatMessage(role:, content: text)))
        option.None -> decode.failure(IgnoredOutput, "could not parse role")
      }
    }
    "function_call" -> {
      use id <- decode.field("id", decode.string)
      use call_id <- decode.field("call_id", decode.string)
      use name <- decode.field("name", decode.string)
      use arguments <- decode.field("arguments", decode.string)
      decode.success(
        FunctionCallOutput(types.ToolCall(
          id:,
          call_id:,
          name:,
          arguments:,
          thought_signature: option.None,
        )),
      )
    }
    _ -> decode.success(IgnoredOutput)
  }
}

fn chat_completion_decoder() -> decode.Decoder(ChatCompletion) {
  use id <- decode.field("id", decode.string)
  use output_items <- decode.field("output", decode.list(output_item_decoder()))
  let #(output, tool_calls) =
    output_items
    |> list.fold(#([], []), fn(acc, item) {
      case item {
        MessageOutput(message) -> #([message, ..acc.0], acc.1)
        FunctionCallOutput(call) -> #(acc.0, [call, ..acc.1])
        IgnoredOutput -> acc
      }
    })
  use usage <- decode.field("usage", decode.optional(usage_decoder()))
  decode.success(ChatCompletion(
    id:,
    output: list.reverse(output),
    tool_calls: list.reverse(tool_calls),
    usage:,
  ))
}

@internal
pub fn decode_response(
  body: String,
) -> Result(ChatCompletion, json.DecodeError) {
  json.parse(body, chat_completion_decoder())
}

@internal
pub fn response_to_completion(
  chat_completion: ChatCompletion,
) -> Result(types.Completion, types.CompletionError) {
  let content = case chat_completion.output {
    [] -> option.None
    messages ->
      messages
      |> list.map(fn(message) { message.content })
      |> string.join("")
      |> option.Some
  }

  case content, chat_completion.tool_calls {
    option.None, [] -> Error(types.ApiError("The GPT API returned no output"))
    _, _ ->
      Ok(types.Completion(
        content:,
        tool_calls: chat_completion.tool_calls,
        response_id: option.Some(chat_completion.id),
      ))
  }
}

fn send_request(
  client: GPTClientInternal,
  request_body: ChatCompletionRequest,
  system_instruction: option.Option(String),
) -> Result(ChatCompletion, types.CompletionError) {
  let json_body = encode_request(request_body, system_instruction)
  let req =
    request.new()
    |> request.set_method(http.Post)
    |> request.set_host("api.openai.com")
    |> request.set_path("/v1/responses")
    |> request.set_header("content-type", "application/json")
    |> request.set_header("Authorization", "Bearer " <> client.api_key)
    |> request.set_body(json.to_string(json_body))

  case hackney.send(req) {
    Ok(resp) ->
      case resp.status {
        200 ->
          case decode_response(resp.body) {
            Ok(response) -> Ok(response)
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

pub fn generate_content(
  client: GPTClientInternal,
  model: String,
  messages: List(types.ChatMessage),
  system_instruction: option.Option(String),
  tools: List(types.Tool),
  tool_outputs: List(types.ToolOutput),
  previous_response_id: option.Option(String),
) -> Result(types.Completion, types.CompletionError) {
  let request_body =
    ChatCompletionRequest(
      model:,
      input: messages,
      tools:,
      tool_outputs:,
      previous_response_id:,
    )

  use response <- result.try(send_request(
    client,
    request_body,
    system_instruction,
  ))
  response_to_completion(response)
}
