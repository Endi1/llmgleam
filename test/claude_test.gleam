import gleam/dynamic/decode
import gleam/json
import gleam/option
import llmgleam/claude
import llmgleam/messages
import llmgleam/schema
import llmgleam/tools
import llmgleam/types

fn weather_tool() -> types.Tool {
  tools.function(
    name: "get_weather",
    description: "Get the weather",
    parameters: schema.parameters([
      schema.property("city", schema.string()),
    ]),
  )
}

pub fn tool_request_encoding_test() {
  let request =
    claude.MessagesRequest(
      model: "claude-sonnet-4-5",
      messages: [messages.user("Weather in Paris?")],
      system: option.Some("Be concise"),
      max_tokens: 1024,
      tools: [weather_tool()],
      tool_exchanges: [],
      pending_completion: option.None,
      tool_outputs: [],
    )

  let assert Ok(encoded) = claude.encode_request(request)
  assert json.to_string(encoded)
    == "{\"system\":\"Be concise\",\"tools\":[{\"name\":\"get_weather\",\"description\":\"Get the weather\",\"input_schema\":{\"type\":\"object\",\"properties\":{\"city\":{\"type\":\"string\"}},\"required\":[\"city\"],\"additionalProperties\":false},\"strict\":true}],\"model\":\"claude-sonnet-4-5\",\"messages\":[{\"role\":\"user\",\"content\":\"Weather in Paris?\"}],\"max_tokens\":1024}"
}

pub fn tool_response_decoding_test() {
  let body =
    "{\"id\":\"msg_123\",\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"I'll check.\"},{\"type\":\"tool_use\",\"id\":\"toolu_123\",\"name\":\"get_weather\",\"input\":{\"city\":\"Paris\",\"days\":[1,2],\"metric\":true,\"optional\":null,\"ratio\":1.5}}],\"usage\":{\"input_tokens\":10,\"output_tokens\":5}}"

  let assert Ok(response) = claude.decode_response(body)
  let assert Ok(completion) = claude.response_to_completion(response)
  assert completion.content == option.Some("I'll check.")
  assert completion.response_id == option.Some("msg_123")
  let assert [call] = completion.tool_calls
  assert call.id == "toolu_123"
  assert call.call_id == "toolu_123"
  assert call.name == "get_weather"

  let assert Ok(arguments) =
    tools.decode_arguments(call, using: {
      use city <- decode.field("city", decode.string)
      use optional <- decode.field("optional", decode.optional(decode.string))
      use ratio <- decode.field("ratio", decode.float)
      decode.success(#(city, optional, ratio))
    })
  assert arguments == #("Paris", option.None, 1.5)
}

pub fn tool_continuation_encoding_test() {
  let call =
    types.ToolCall(
      id: "toolu_123",
      call_id: "toolu_123",
      name: "get_weather",
      arguments: "{\"city\":\"Paris\"}",
    )
  let completion =
    types.Completion(
      content: option.Some("I'll check."),
      tool_calls: [call],
      response_id: option.Some("msg_123"),
    )
  let request =
    claude.MessagesRequest(
      model: "claude-sonnet-4-5",
      messages: [messages.user("Weather in Paris?")],
      system: option.None,
      max_tokens: 1024,
      tools: [weather_tool()],
      tool_exchanges: [],
      pending_completion: option.Some(completion),
      tool_outputs: [
        types.ToolOutput(call_id: "toolu_123", output: "18 degrees Celsius"),
      ],
    )

  let assert Ok(encoded) = claude.encode_request(request)
  assert json.to_string(encoded)
    == "{\"tools\":[{\"name\":\"get_weather\",\"description\":\"Get the weather\",\"input_schema\":{\"type\":\"object\",\"properties\":{\"city\":{\"type\":\"string\"}},\"required\":[\"city\"],\"additionalProperties\":false},\"strict\":true}],\"model\":\"claude-sonnet-4-5\",\"messages\":[{\"role\":\"user\",\"content\":\"Weather in Paris?\"},{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"I'll check.\"},{\"type\":\"tool_use\",\"id\":\"toolu_123\",\"name\":\"get_weather\",\"input\":{\"city\":\"Paris\"}}]},{\"role\":\"user\",\"content\":[{\"type\":\"tool_result\",\"tool_use_id\":\"toolu_123\",\"content\":\"18 degrees Celsius\"}]}],\"max_tokens\":1024}"
}
