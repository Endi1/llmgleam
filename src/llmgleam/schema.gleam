import gleam/json
import gleam/list

/// A type-safe subset of JSON Schema supported by function tools.
pub opaque type Schema {
  StringSchema
  StringEnumSchema(values: List(String))
  IntegerSchema
  NumberSchema
  BooleanSchema
  ArraySchema(items: Schema)
  ObjectSchema(properties: List(Property))
  NullableSchema(schema: Schema)
  DescribedSchema(schema: Schema, description: String)
}

/// A named property in an object schema.
pub opaque type Property {
  Property(name: String, schema: Schema)
}

/// The top-level object schema for a function's arguments.
///
/// Every property is required and additional properties are disabled, making
/// these parameters compatible with OpenAI strict mode. Use `nullable` when a
/// required argument may have no value.
pub opaque type Parameters {
  Parameters(properties: List(Property))
}

/// Creates the top-level parameters for a function tool.
pub fn parameters(properties: List(Property)) -> Parameters {
  Parameters(properties:)
}

/// Creates a named object property.
pub fn property(name: String, schema: Schema) -> Property {
  Property(name:, schema:)
}

/// Creates a string schema.
pub fn string() -> Schema {
  StringSchema
}

/// Creates a string schema restricted to one or more values.
pub fn string_enum(first: String, rest: List(String)) -> Schema {
  StringEnumSchema([first, ..rest])
}

/// Creates an integer schema.
pub fn integer() -> Schema {
  IntegerSchema
}

/// Creates a number schema.
pub fn number() -> Schema {
  NumberSchema
}

/// Creates a boolean schema.
pub fn boolean() -> Schema {
  BooleanSchema
}

/// Creates an array schema.
pub fn array(items: Schema) -> Schema {
  ArraySchema(items:)
}

/// Creates an object schema.
///
/// Every property is required and additional properties are disabled.
pub fn object(properties: List(Property)) -> Schema {
  ObjectSchema(properties:)
}

/// Allows a schema's value to be `null`.
pub fn nullable(schema: Schema) -> Schema {
  NullableSchema(schema:)
}

/// Adds a description to any schema.
pub fn described(schema: Schema, description: String) -> Schema {
  case schema {
    DescribedSchema(inner, _) -> DescribedSchema(inner, description)
    _ -> DescribedSchema(schema, description)
  }
}

fn object_fields(properties: List(Property)) -> List(#(String, json.Json)) {
  let encoded_properties =
    properties
    |> list.map(fn(property) { #(property.name, encode(property.schema)) })
    |> json.object
  let required =
    properties
    |> list.map(fn(property) { property.name })
    |> json.array(json.string)

  [
    #("type", json.string("object")),
    #("properties", encoded_properties),
    #("required", required),
    #("additionalProperties", json.bool(False)),
  ]
}

fn fields(schema: Schema) -> List(#(String, json.Json)) {
  case schema {
    StringSchema -> [#("type", json.string("string"))]
    StringEnumSchema(values) -> [
      #("type", json.string("string")),
      #("enum", json.array(values, json.string)),
    ]
    IntegerSchema -> [#("type", json.string("integer"))]
    NumberSchema -> [#("type", json.string("number"))]
    BooleanSchema -> [#("type", json.string("boolean"))]
    ArraySchema(items) -> [
      #("type", json.string("array")),
      #("items", encode(items)),
    ]
    ObjectSchema(properties) -> object_fields(properties)
    NullableSchema(schema) -> [
      #(
        "anyOf",
        json.preprocessed_array([
          encode(schema),
          json.object([#("type", json.string("null"))]),
        ]),
      ),
    ]
    DescribedSchema(schema, description) -> [
      #("description", json.string(description)),
      ..fields(schema)
    ]
  }
}

fn encode(schema: Schema) -> json.Json {
  schema
  |> fields
  |> json.object
}

/// Encodes typed function parameters as JSON Schema.
pub fn to_json(parameters: Parameters) -> json.Json {
  parameters.properties
  |> object_fields
  |> json.object
}
