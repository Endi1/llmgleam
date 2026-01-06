import llmgleam/messages
import envoy
import gleam/option
import gleam/result
import gleam/string
import llmgleam
import llmgleam/client
import llmgleam/types

pub fn generate_content_gemini_test() {
  case envoy.get("RUN_INTEGRATION_TESTS") {
    Error(Nil) -> Nil
    Ok(_) -> {
      let gemini_key_result = envoy.get("GEMINI_KEY")
      assert result.is_error(gemini_key_result) != True

      let gemini_key = gemini_key_result |> result.unwrap("default-key")
      let client = client.Gemini |> llmgleam.new_client(gemini_key)
      let completion =
        llmgleam.completion(
          client,
          "gemini-2.5-flash",
          [
            messages.user("Hello, how are you?")
          ],
          option.None,
        )
      assert result.is_ok(completion) == True
      let _ =
        result.map(completion, fn(c) {
          assert string.length(c.content) > 0
        })
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
        llmgleam.completion(
          client,
          "gemini-2.5-flash",
          [
            messages.user("hello, how are you?"),
          ],
          option.Some("you are a helpful conversationalist"),
        )
      assert result.is_ok(completion) == True
      let _ =
        result.map(completion, fn(c) {
          assert string.length(c.content) > 0
        })
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
        llmgleam.completion(
          client,
          "gpt-5-nano",
          [
            types.ChatMessage(content: "Hello, how are you", role: types.User),
          ],
          option.None,
        )

      assert result.is_ok(completion) == True
      let _ =
        result.map(completion, fn(c) {
          assert string.length(c.content) > 0
        })
      Nil
    }
  }
}
