import gleam/dynamic/decode
import gleam/json
import gleam/option
import llmgleam/gpt
import llmgleam/messages
import llmgleam/schema
import llmgleam/tools
import llmgleam/types

type WeatherArguments {
  WeatherArguments(city: String)
}

pub fn tool_request_encoding_test() {
  let parameters = schema.parameters([])
  let tool = tools.function("get_weather", "Get the weather", parameters)
  let request =
    gpt.ChatCompletionRequest(
      model: "gpt-5-nano",
      input: [messages.user("Weather in Paris?")],
      tools: [tool],
      tool_outputs: [
        types.ToolOutput(
          call_id: "call_123",
          tool_name: option.Some("get_weather"),
          output: "sunny",
        ),
      ],
      previous_response_id: option.Some("resp_123"),
    )

  let encoded =
    gpt.encode_request(request, option.Some("Be concise"))
    |> json.to_string

  assert encoded
    == "{\"instructions\":\"Be concise\",\"previous_response_id\":\"resp_123\",\"tools\":[{\"type\":\"function\",\"name\":\"get_weather\",\"description\":\"Get the weather\",\"parameters\":{\"type\":\"object\",\"properties\":{},\"required\":[],\"additionalProperties\":false},\"strict\":true}],\"model\":\"gpt-5-nano\",\"input\":[{\"role\":\"user\",\"content\":\"Weather in Paris?\"},{\"type\":\"function_call_output\",\"call_id\":\"call_123\",\"output\":\"sunny\"}]}"
}

pub fn function_call_response_decoding_test() {
  let body =
    "{\"id\":\"resp_123\",\"output\":[{\"type\":\"reasoning\",\"id\":\"rs_123\"},{\"type\":\"function_call\",\"id\":\"fc_123\",\"call_id\":\"call_123\",\"name\":\"get_weather\",\"arguments\":\"{\\\"city\\\":\\\"Paris\\\"}\"},{\"type\":\"message\",\"role\":\"assistant\",\"content\":[{\"type\":\"output_text\",\"text\":\"Let me check.\"}]}],\"usage\":{\"input_tokens\":10,\"output_tokens\":5,\"total_tokens\":15}}"

  let assert Ok(completion) = gpt.decode_response(body)
  assert completion.id == "resp_123"
  let assert [message] = completion.output
  assert message.content == "Let me check."
  assert message.role == types.Assistant
  let assert [call] = completion.tool_calls
  assert call.id == "fc_123"
  assert call.call_id == "call_123"
  assert call.name == "get_weather"
  assert call.arguments == "{\"city\":\"Paris\"}"
}

pub fn tool_call_maps_to_completion_test() {
  let call =
    types.ToolCall(
      id: "fc_123",
      call_id: "call_123",
      name: "get_weather",
      arguments: "{\"city\":\"Paris\"}",
      thought_signature: option.None,
    )
  let response =
    gpt.ChatCompletion(
      id: "resp_123",
      output: [],
      tool_calls: [call],
      usage: option.None,
    )

  let assert Ok(completion) = gpt.response_to_completion(response)
  assert completion.content == option.None
  assert completion.tool_calls == [call]
  assert completion.response_id == option.Some("resp_123")
}

pub fn tool_arguments_decoding_test() {
  let call =
    types.ToolCall(
      id: "fc_123",
      call_id: "call_123",
      name: "get_weather",
      arguments: "{\"city\":\"Paris\"}",
      thought_signature: option.None,
    )
  let decoder = {
    use city <- decode.field("city", decode.string)
    decode.success(WeatherArguments(city:))
  }

  let assert Ok(WeatherArguments("Paris")) =
    tools.decode_arguments(call, using: decoder)
  Nil
}

pub fn tool_output_helpers_test() {
  let call =
    types.ToolCall(
      id: "fc_123",
      call_id: "call_123",
      name: "get_weather",
      arguments: "{}",
      thought_signature: option.None,
    )

  assert tools.output(call, "sunny")
    == types.ToolOutput(
      call_id: "call_123",
      tool_name: option.Some("get_weather"),
      output: "sunny",
    )
  assert tools.output_for("call_456", "rainy")
    == types.ToolOutput(
      call_id: "call_456",
      tool_name: option.None,
      output: "rainy",
    )
}
