import envoy
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

      let gemini_key = result.unwrap(gemini_key_result, "default-key")
      let client = llmgleam.new_client(client.Gemini, gemini_key)
      let completion =
        llmgleam.completion(client, "gemini-2.5-flash", [
          types.ChatMessage(content: "Hello, how are you", role: types.User),
        ])
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
        llmgleam.completion(client, "gpt-5-nano", [
          types.ChatMessage(content: "answer in 5 words", role: types.System),
          types.ChatMessage(content: "Hello, how are you", role: types.User),
        ])

      assert result.is_ok(completion) == True
      let _ =
        result.map(completion, fn(c) {
          assert string.length(c.content) > 0
        })
      Nil
    }
  }
}
