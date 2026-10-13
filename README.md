# LLMGleam

A Gleam library for interacting with Large Language Model APIs.
Currently supports Google's Gemini, OpenAI's GPT, and Anthropic's Claude APIs
with a clean, type-safe interface.

## Features

- 🔒 **Type-safe**: Leverages Gleam's type system for reliable API
  interactions
- 🌟 **Clean API**: Fluent builder pattern for constructing requests
- 🔌 **Extensible**: Designed to support multiple LLM providers
- 🛠️ **Tool calling**: Define and execute function tools with GPT and Claude
- ⚡ **Async**: Built on Gleam's concurrent model

## Installation

`gleam add llmgleam`

## Quick Start

``` gleam
import gleam/option
import llmgleam
import llmgleam/client
import llmgleam/messages

pub fn main() {
  // Create a client
  let client = llmgleam.new_client(client.Gemini, "your-api-key-here")

  // Get completion using the builder pattern
  let result =
    client
    |> client.request()
    |> client.with_message(messages.user("Hello, how are you?"))
    |> client.completion("gemini-2.5-flash")

  case result {
    Ok(completion) -> {
      io.println("Response: " <> option.unwrap(completion.content, ""))
    }
    Error(error) -> {
      io.println("Error: " <> string.inspect(error))
    }
  }
}
```

## API Reference

### Creating a Client

``` gleam
import llmgleam
import llmgleam/client

// For Gemini
let gemini_client = llmgleam.new_client(client.Gemini, "your-gemini-api-key")

// For GPT
let gpt_client = llmgleam.new_client(client.GPT, "your-openai-api-key")

// For Claude
let claude_client = llmgleam.new_client(client.Claude, "your-anthropic-api-key")
```

### Building Requests

The library uses a fluent builder pattern for constructing requests:

``` gleam
import llmgleam/client
import llmgleam/messages

let completion =
  client
  |> client.request()
  |> client.with_message(messages.user("Hello, how are you?"))
  |> client.with_system_instruction("You are a helpful assistant")
  |> client.completion("gemini-2.5-flash")
```

### Messages

``` gleam
import llmgleam/messages

// Create a user message
let user_msg = messages.user("Hello, how are you?")

// System instructions are added via with_system_instruction
```

### Tool Calling

Function tools use a typed JSON Schema builder for their arguments. Tool
arguments returned by the model are JSON-encoded strings and should be decoded
and validated before use with `tools.decode_arguments` and a Gleam decoder.

``` gleam
import llmgleam/client
import llmgleam/messages
import llmgleam/schema
import llmgleam/tools

let weather_tool =
  tools.function(
    name: "get_weather",
    description: "Get the current weather for a location",
    parameters: schema.parameters([
      schema.property(
        "location",
        schema.string()
        |> schema.described("The city and country, such as Paris, France"),
      ),
    ]),
  )

let request =
  gpt_client
  |> client.request()
  |> client.with_message(messages.user("What is the weather in Paris?"))
  |> client.with_tool(weather_tool)

let assert Ok(first) = client.completion(request, "gpt-5-nano")
let assert [call, ..] = first.tool_calls

// Run the function in your application, then return its output to GPT.
let output = tools.output(call, "{\"temperature\":18,\"unit\":\"celsius\"}")
let assert Ok(continued) = client.continue_from(request, first)
let final =
  continued
  |> client.with_tool_output(output)
  |> client.completion("gpt-5-nano")
```

A response can contain text, tool calls, or both. Text is available as
`completion.content: Option(String)`. Models can request multiple calls, in
which case all outputs should be added with `client.with_tool_outputs` before
continuing.

Tool calling supports GPT through OpenAI's Responses API and Claude through
Anthropic's Messages API. GPT continues from a response ID; Claude continues by
sending the prior assistant tool-use blocks and user tool-result blocks back in
conversation order. The same client API is used for both providers.

### Functions

1.  `llmgleam.new_client(provider: Provider, api_key: String) -> Client`

    Creates a new LLM client for the specified provider.

2.  `client.request(client: Client) -> Request`

    Initializes a new request builder from a client.

3.  `client.with_message(request: Request, message: Message) -> Request`

    Adds a message to the request.

4.  `client.with_system_instruction(request: Request, instruction: String) -> Request`

    Adds a system instruction to the request.

5.  `client.completion(request: Request, model: String) -> Result(Completion, CompletionError)`

    Executes the request and returns text, tool calls, or both.

6.  `client.with_tool(request: Request, tool: Tool) -> Request`

    Adds a function tool to a GPT request.

7.  `client.continue_from(request: Request, completion: Completion) -> Result(Request, CompletionError)`

    Starts the next turn of a GPT or Claude tool-calling exchange.

## Supported Providers

### Google Gemini

- **Provider**: `client.Gemini`
- **Authentication**: API key via Google AI Studio

### OpenAI GPT

- **Provider**: `client.GPT`
- **Authentication**: API key via OpenAI

### Anthropic Claude

- **Provider**: `client.Claude`
- **Authentication**: API key via Anthropic

## Example with System Instructions

``` gleam
import llmgleam
import llmgleam/client
import llmgleam/messages

let client = llmgleam.new_client(client.Gemini, "your-api-key")

let completion =
  client
  |> client.request()
  |> client.with_message(messages.user("hello, how are you?"))
  |> client.with_system_instruction("you are a helpful conversationalist")
  |> client.completion("gemini-2.5-flash")
```

## Development

### Running Tests

``` bash
gleam test
```

For integration tests (requires API keys):

``` bash
RUN_INTEGRATION_TESTS=1 GEMINI_KEY=your-key GPT_KEY=your-key gleam test
```

### Building

``` bash
gleam build
```

## Contributing

Contributions are welcome! Areas for improvement:

- [x] Add support for OpenAI GPT models
- [x] Add support for Gemini API
- [ ] Add support for Gemini through vertex.ai
- [x] Add support for Anthropic Claude
- [ ] Add streaming support
- [x] Add function calling support for GPT and Claude
- [ ] Add image/multimodal support

## License

This project is licensed under the MIT License - see the LICENSE file
for details.
