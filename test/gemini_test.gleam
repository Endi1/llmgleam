import gleam/dynamic/decode
import gleam/json
import gleam/option
import llmgleam/gemini
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
    gemini.GenerateContentRequest(
      contents: [
        gemini.Content(role: option.Some(types.User), parts: [
          gemini.TextPart("Weather in Paris?"),
        ]),
      ],
      tools: [weather_tool()],
      tool_exchanges: [],
      pending_completion: option.None,
      tool_outputs: [],
    )

  let assert Ok(encoded) =
    gemini.encode_request(request, option.Some("Be concise"))
  assert json.to_string(encoded)
    == "{\"systemInstruction\":{\"parts\":[{\"text\":\"Be concise\"}]},\"tools\":[{\"functionDeclarations\":[{\"name\":\"get_weather\",\"description\":\"Get the weather\",\"parameters\":{\"type\":\"object\",\"properties\":{\"city\":{\"type\":\"string\"}},\"required\":[\"city\"]}}]}],\"contents\":[{\"role\":\"user\",\"parts\":[{\"text\":\"Weather in Paris?\"}]}]}"
}

pub fn tool_response_decoding_test() {
  let body =
    "{\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"I'll check.\"},{\"thoughtSignature\":\"signature-123\",\"functionCall\":{\"id\":\"call-123\",\"name\":\"get_weather\",\"args\":{\"city\":\"Paris\",\"metric\":true}}}]},\"finishReason\":\"STOP\"}]}"

  let assert Ok(response) = gemini.decode_response(body)
  let assert Ok(completion) = gemini.response_to_completion(response)
  assert completion.content == option.Some("I'll check.")
  assert completion.response_id == option.None
  let assert [call] = completion.tool_calls
  assert call.id == "call-123"
  assert call.call_id == "call-123"
  assert call.name == "get_weather"
  assert call.thought_signature == option.Some("signature-123")

  let assert Ok(city) =
    tools.decode_arguments(call, using: {
      use city <- decode.field("city", decode.string)
      decode.success(city)
    })
  assert city == "Paris"
}

pub fn tool_continuation_encoding_test() {
  let call =
    types.ToolCall(
      id: "call-123",
      call_id: "call-123",
      name: "get_weather",
      arguments: "{\"city\":\"Paris\"}",
      thought_signature: option.Some("signature-123"),
    )
  let completion =
    types.Completion(
      content: option.Some("I'll check."),
      tool_calls: [call],
      response_id: option.None,
    )
  let request =
    gemini.GenerateContentRequest(
      contents: [
        gemini.Content(role: option.Some(types.User), parts: [
          gemini.TextPart("Weather in Paris?"),
        ]),
      ],
      tools: [weather_tool()],
      tool_exchanges: [],
      pending_completion: option.Some(completion),
      tool_outputs: [
        types.ToolOutput(
          call_id: "call-123",
          tool_name: option.Some("get_weather"),
          output: "{\"temperature\":18,\"unit\":\"celsius\"}",
        ),
      ],
    )

  let assert Ok(encoded) = gemini.encode_request(request, option.None)
  assert json.to_string(encoded)
    == "{\"tools\":[{\"functionDeclarations\":[{\"name\":\"get_weather\",\"description\":\"Get the weather\",\"parameters\":{\"type\":\"object\",\"properties\":{\"city\":{\"type\":\"string\"}},\"required\":[\"city\"]}}]}],\"contents\":[{\"role\":\"user\",\"parts\":[{\"text\":\"Weather in Paris?\"}]},{\"parts\":[{\"text\":\"I'll check.\"},{\"thoughtSignature\":\"signature-123\",\"functionCall\":{\"id\":\"call-123\",\"name\":\"get_weather\",\"args\":{\"city\":\"Paris\"}}}],\"role\":\"model\"},{\"parts\":[{\"functionResponse\":{\"id\":\"call-123\",\"name\":\"get_weather\",\"response\":{\"result\":{\"unit\":\"celsius\",\"temperature\":18}}}}],\"role\":\"user\"}]}"
}
