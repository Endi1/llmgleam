import gleam/json
import llmgleam/schema

pub fn typed_parameters_encoding_test() {
  let parameters =
    schema.parameters([
      schema.property(
        "location",
        schema.string() |> schema.described("City and country"),
      ),
      schema.property(
        "units",
        schema.string_enum("celsius", ["fahrenheit"])
          |> schema.nullable,
      ),
      schema.property(
        "options",
        schema.object([
          schema.property("days", schema.integer()),
          schema.property("alerts", schema.boolean()),
        ]),
      ),
      schema.property("scores", schema.array(schema.number())),
    ])

  assert parameters
    |> schema.to_json
    |> json.to_string
    == "{\"type\":\"object\",\"properties\":{\"location\":{\"description\":\"City and country\",\"type\":\"string\"},\"units\":{\"anyOf\":[{\"type\":\"string\",\"enum\":[\"celsius\",\"fahrenheit\"]},{\"type\":\"null\"}]},\"options\":{\"type\":\"object\",\"properties\":{\"days\":{\"type\":\"integer\"},\"alerts\":{\"type\":\"boolean\"}},\"required\":[\"days\",\"alerts\"],\"additionalProperties\":false},\"scores\":{\"type\":\"array\",\"items\":{\"type\":\"number\"}}},\"required\":[\"location\",\"units\",\"options\",\"scores\"],\"additionalProperties\":false}"
}
