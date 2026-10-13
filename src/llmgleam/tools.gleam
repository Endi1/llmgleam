import gleam/dynamic/decode
import gleam/json
import gleam/option
import llmgleam/schema
import llmgleam/types

/// Defines a function tool using a JSON Schema for its arguments.
///
/// Strict schema validation is requested on providers that expose per-tool
/// strict mode. The generated schema marks every property as required.
pub fn function(
  name name: String,
  description description: String,
  parameters parameters: schema.Parameters,
) -> types.Tool {
  types.Tool(name:, description:, parameters:, strict: True)
}

/// Defines a function tool and explicitly controls strict schema validation.
pub fn function_with_strictness(
  name name: String,
  description description: String,
  parameters parameters: schema.Parameters,
  strict strict: Bool,
) -> types.Tool {
  types.Tool(name:, description:, parameters:, strict:)
}

/// Decodes and validates a tool call's JSON arguments.
pub fn decode_arguments(
  call: types.ToolCall,
  using decoder: decode.Decoder(arguments),
) -> Result(arguments, json.DecodeError) {
  json.parse(call.arguments, decoder)
}

pub fn output(call: types.ToolCall, output: String) -> types.ToolOutput {
  types.ToolOutput(
    call_id: call.call_id,
    tool_name: option.Some(call.name),
    output:,
  )
}

pub fn output_for(call_id: String, output: String) -> types.ToolOutput {
  types.ToolOutput(call_id:, tool_name: option.None, output:)
}
