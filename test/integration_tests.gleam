import envoy
import gleam/option
import gleam/result
import gleam/string
import llmgleam
import llmgleam/client
import llmgleam/messages
import llmgleam/schema
import llmgleam/tools
import llmgleam/types

fn assert_completion_has_text(completion: types.Completion) -> Nil {
  let content = option.unwrap(completion.content, "")
  assert string.length(content) > 0
  Nil
}

pub fn generate_content_gemini_test() {
  case envoy.get("RUN_INTEGRATION_TESTS") {
    Error(Nil) -> Nil
    Ok(_) -> {
      let gemini_key_result = envoy.get("GEMINI_KEY")
      assert result.is_error(gemini_key_result) != True

      let gemini_key = gemini_key_result |> result.unwrap("default-key")
      let client = client.Gemini |> llmgleam.new_client(gemini_key)
      let completion =
        client
        |> client.request()
        |> client.with_message(messages.user("Hello, how are you?"))
        |> client.completion("gemini-2.5-flash")
      assert result.is_ok(completion) == True
      let _ = result.map(completion, assert_completion_has_text)
      Nil
    }
  }
}

pub fn generate_content_gemini_system_test() {
  case envoy.get("RUN_INTEGRATION_TESTS") {
    Error(Nil) -> Nil
    Ok(_) -> {
      let gemini_key_result = envoy.get("GEMINI_KEY")
      assert result.is_error(gemini_key_result) != True

      let gemini_key = result.unwrap(gemini_key_result, "default-key")
      let client = llmgleam.new_client(client.Gemini, gemini_key)
      let completion =
        client
        |> client.request()
        |> client.with_message(messages.user("hello, how are you?"))
        |> client.with_system_instruction("you are a helpful conversationalist")
        |> client.completion("gemini-2.5-flash")
      assert result.is_ok(completion) == True
      let _ = result.map(completion, assert_completion_has_text)
      Nil
    }
  }
}

pub fn generate_content_gpt_test() {
  case envoy.get("RUN_INTEGRATION_TESTS") {
    Error(Nil) -> Nil
    Ok(_) -> {
      let gpt_key_result = envoy.get("GPT_KEY")
      assert result.is_error(gpt_key_result) != True

      let gpt_key = result.unwrap(gpt_key_result, "default-key")
      let client = llmgleam.new_client(client.GPT, gpt_key)
      let completion =
        client
        |> client.request()
        |> client.with_message(messages.user("Hello, how are you?"))
        |> client.completion("gpt-5-nano")

      assert result.is_ok(completion) == True
      let _ = result.map(completion, assert_completion_has_text)
      Nil
    }
  }
}

pub fn generate_content_gpt_tool_test() {
  case envoy.get("RUN_INTEGRATION_TESTS") {
    Error(Nil) -> Nil
    Ok(_) -> {
      let gpt_key_result = envoy.get("GPT_KEY")
      assert result.is_error(gpt_key_result) != True

      let gpt_key = result.unwrap(gpt_key_result, "default-key")
      let gpt_client = llmgleam.new_client(client.GPT, gpt_key)

      let weather_tool =
        tools.function(
          name: "get_weather",
          description: "Get the current weather for a city",
          parameters: schema.parameters([
            schema.property(
              "city",
              schema.string()
                |> schema.described("The city whose weather should be returned"),
            ),
          ]),
        )

      let request =
        gpt_client
        |> client.request()
        |> client.with_system_instruction(
          "Call get_weather exactly once, then answer using its output.",
        )
        |> client.with_message(messages.user("What is the weather in Paris?"))
        |> client.with_tool(weather_tool)

      let assert Ok(first) = request |> client.completion("gpt-5-nano")
      let assert [call, ..] = first.tool_calls
      assert call.name == "get_weather"

      let assert Ok(continued) = client.continue_from(request, first)
      let final =
        continued
        |> client.with_tool_output(tools.output(
          call,
          "{\"temperature\":18,\"unit\":\"celsius\"}",
        ))
        |> client.completion("gpt-5-nano")
      assert result.is_ok(final) == True
      Nil
    }
  }
}

pub fn generate_content_claude_tool_test() {
  case envoy.get("RUN_INTEGRATION_TESTS") {
    Error(Nil) -> Nil
    Ok(_) -> {
      let claude_key_result = envoy.get("CLAUDE_KEY")
      assert result.is_error(claude_key_result) != True

      let claude_key = result.unwrap(claude_key_result, "default-key")
      let claude_client = llmgleam.new_client(client.Claude, claude_key)
      let weather_tool =
        tools.function(
          name: "get_weather",
          description: "Get the current weather for a city",
          parameters: schema.parameters([
            schema.property(
              "city",
              schema.string()
                |> schema.described("The city whose weather should be returned"),
            ),
          ]),
        )
      let request =
        claude_client
        |> client.request()
        |> client.with_system_instruction(
          "Call get_weather exactly once, then answer using its output.",
        )
        |> client.with_message(messages.user("What is the weather in Paris?"))
        |> client.with_tool(weather_tool)

      let assert Ok(first) = request |> client.completion("claude-sonnet-4-5")
      let assert [call, ..] = first.tool_calls
      assert call.name == "get_weather"

      let assert Ok(continued) = client.continue_from(request, first)
      let final =
        continued
        |> client.with_tool_output(tools.output(
          call,
          "{\"temperature\":18,\"unit\":\"celsius\"}",
        ))
        |> client.completion("claude-sonnet-4-5")
      assert result.is_ok(final) == True
      Nil
    }
  }
}

pub fn generate_content_claude_test() {
  case envoy.get("RUN_INTEGRATION_TESTS") {
    Error(Nil) -> Nil
    Ok(_) -> {
      let claude_key_result = envoy.get("CLAUDE_KEY")
      assert result.is_error(claude_key_result) != True

      let claude_key = result.unwrap(claude_key_result, "default-key")
      let client = llmgleam.new_client(client.Claude, claude_key)
      let completion =
        client
        |> client.request()
        |> client.with_message(messages.user("Hello, how are you?"))
        |> client.completion("claude-sonnet-4-5")

      assert result.is_ok(completion) == True
      let _ = result.map(completion, assert_completion_has_text)
      Nil
    }
  }
}

pub fn generate_content_claude_system_test() {
  case envoy.get("RUN_INTEGRATION_TESTS") {
    Error(Nil) -> Nil
    Ok(_) -> {
      let claude_key_result = envoy.get("CLAUDE_KEY")
      assert result.is_error(claude_key_result) != True

      let claude_key = result.unwrap(claude_key_result, "default-key")
      let client = llmgleam.new_client(client.Claude, claude_key)
      let completion =
        client
        |> client.request()
        |> client.with_message(messages.user("hello, how are you?"))
        |> client.with_system_instruction("you are a helpful conversationalist")
        |> client.completion("claude-sonnet-4-5")
      assert result.is_ok(completion) == True
      let _ = result.map(completion, assert_completion_has_text)
      Nil
    }
  }
}

pub fn generate_content_gpt_system_test() {
  case envoy.get("RUN_INTEGRATION_TESTS") {
    Error(Nil) -> Nil
    Ok(_) -> {
      let gpt_key_result = envoy.get("GPT_KEY")
      assert result.is_error(gpt_key_result) != True

      let gpt_key = result.unwrap(gpt_key_result, "default-key")
      let client = llmgleam.new_client(client.GPT, gpt_key)
      let completion =
        client
        |> client.request()
        |> client.with_message(messages.user("hello, how are you?"))
        |> client.with_system_instruction("you are a helpful conversationalist")
        |> client.completion("gpt-5-nano")

      assert result.is_ok(completion) == True
      let _ = result.map(completion, assert_completion_has_text)
      Nil
    }
  }
}
