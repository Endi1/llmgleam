import gleam/list
import gleam/option
import llmgleam/claude
import llmgleam/gemini
import llmgleam/gpt
import llmgleam/types

pub type Provider {
  Gemini
  GPT
  Claude
}

pub opaque type Client {
  GeminiClient(client: gemini.GeminiClientInternal)
  GPTClient(client: gpt.GPTClientInternal)
  ClaudeClient(client: claude.ClaudeClientInternal)
}

pub opaque type Request {
  Request(
    messages: List(types.ChatMessage),
    client: Client,
    system_instruction: option.Option(String),
    tools: List(types.Tool),
    tool_outputs: List(types.ToolOutput),
    previous_response_id: option.Option(String),
    tool_exchanges: List(#(types.Completion, List(types.ToolOutput))),
    pending_completion: option.Option(types.Completion),
  )
}

pub fn with_message(request: Request, message: types.ChatMessage) -> Request {
  Request(..request, messages: list.reverse([message, ..request.messages]))
}

pub fn with_messages(
  request: Request,
  messages: List(types.ChatMessage),
) -> Request {
  Request(..request, messages: list.append(request.messages, messages))
}

pub fn new_client(provider: Provider, api_key: String) -> Client {
  case provider {
    Gemini -> GeminiClient(gemini.GeminiClientInternal(api_key:))
    GPT -> GPTClient(gpt.GPTClientInternal(api_key:))
    Claude -> ClaudeClient(claude.ClaudeClientInternal(api_key:))
  }
}

fn client_completion(
  request: Request,
  model: String,
) -> Result(types.Completion, types.CompletionError) {
  case request.client {
    GPTClient(c) ->
      gpt.generate_content(
        c,
        model,
        request.messages,
        request.system_instruction,
        request.tools,
        request.tool_outputs,
        request.previous_response_id,
      )
    GeminiClient(c) ->
      gemini.generate_content(
        c,
        model,
        request.messages,
        request.system_instruction,
        request.tools,
        request.tool_exchanges,
        request.pending_completion,
        request.tool_outputs,
      )
    ClaudeClient(c) ->
      claude.generate_content(
        c,
        model,
        request.messages,
        request.system_instruction,
        request.tools,
        request.tool_exchanges,
        request.pending_completion,
        request.tool_outputs,
      )
  }
}

pub fn request(c: Client) -> Request {
  Request(
    messages: list.new(),
    client: c,
    system_instruction: option.None,
    tools: [],
    tool_outputs: [],
    previous_response_id: option.None,
    tool_exchanges: [],
    pending_completion: option.None,
  )
}

pub fn with_system_instruction(
  request: Request,
  system_instruction: String,
) -> Request {
  Request(..request, system_instruction: option.Some(system_instruction))
}

/// Adds a function tool that GPT may call.
///
/// Tool calling is supported by the GPT, Claude, and Gemini clients.
pub fn with_tool(request: Request, tool: types.Tool) -> Request {
  Request(..request, tools: list.append(request.tools, [tool]))
}

/// Adds function tools that GPT may call.
pub fn with_tools(request: Request, tools: List(types.Tool)) -> Request {
  Request(..request, tools: list.append(request.tools, tools))
}

/// Adds the result of executing a tool call.
pub fn with_tool_output(request: Request, output: types.ToolOutput) -> Request {
  Request(..request, tool_outputs: list.append(request.tool_outputs, [output]))
}

/// Adds the results of executing multiple tool calls.
pub fn with_tool_outputs(
  request: Request,
  outputs: List(types.ToolOutput),
) -> Request {
  Request(..request, tool_outputs: list.append(request.tool_outputs, outputs))
}

/// Continues a tool-calling exchange from an earlier completion.
///
/// Tools and system instructions are retained. GPT continues by response ID;
/// Claude and Gemini retain tool calls and their corresponding results.
pub fn continue_from(
  request: Request,
  completion: types.Completion,
) -> Result(Request, types.CompletionError) {
  case request.client, completion.response_id, completion.tool_calls {
    GPTClient(_), option.Some(response_id), _ ->
      Ok(
        Request(
          ..request,
          messages: [],
          tool_outputs: [],
          previous_response_id: option.Some(response_id),
        ),
      )
    GPTClient(_), option.None, _ ->
      Error(types.ApiError(
        "The completion cannot be continued because it has no response ID",
      ))
    ClaudeClient(_), option.Some(_), [_, ..] -> {
      let exchanges = case request.pending_completion {
        option.Some(previous) ->
          list.append(request.tool_exchanges, [
            #(previous, request.tool_outputs),
          ])
        option.None -> request.tool_exchanges
      }
      Ok(
        Request(
          ..request,
          tool_outputs: [],
          tool_exchanges: exchanges,
          pending_completion: option.Some(completion),
        ),
      )
    }
    ClaudeClient(_), _, [] ->
      Error(types.ApiError(
        "The Claude completion cannot be continued because it has no tool calls",
      ))
    ClaudeClient(_), option.None, [_, ..] ->
      Error(types.ApiError(
        "The completion cannot be continued because it has no response ID",
      ))
    GeminiClient(_), _, [_, ..] -> {
      let exchanges = case request.pending_completion {
        option.Some(previous) ->
          list.append(request.tool_exchanges, [
            #(previous, request.tool_outputs),
          ])
        option.None -> request.tool_exchanges
      }
      Ok(
        Request(
          ..request,
          tool_outputs: [],
          tool_exchanges: exchanges,
          pending_completion: option.Some(completion),
        ),
      )
    }
    GeminiClient(_), _, [] ->
      Error(types.ApiError(
        "The Gemini completion cannot be continued because it has no tool calls",
      ))
  }
}

pub fn completion(
  request: Request,
  model: String,
) -> Result(types.Completion, types.CompletionError) {
  client_completion(request, model)
}
