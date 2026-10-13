import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/json
import gleam/option

@internal
pub opaque type Value {
  StringValue(String)
  BoolValue(Bool)
  IntValue(Int)
  FloatValue(Float)
  ArrayValue(List(Value))
  ObjectValue(Dict(String, Value))
  NullValue
}

@internal
pub fn decoder() -> decode.Decoder(Value) {
  use <- decode.recursive
  decode.one_of(decode.string |> decode.map(StringValue), or: [
    decode.bool |> decode.map(BoolValue),
    decode.int |> decode.map(IntValue),
    decode.float |> decode.map(FloatValue),
    decode.list(decoder()) |> decode.map(ArrayValue),
    decode.dict(decode.string, decoder()) |> decode.map(ObjectValue),
    decode.optional(decode.string)
      |> decode.then(fn(value) {
        case value {
          option.None -> decode.success(NullValue)
          option.Some(_) -> decode.failure(NullValue, "Null")
        }
      }),
  ])
}

@internal
pub fn to_json(value: Value) -> json.Json {
  case value {
    StringValue(value) -> json.string(value)
    BoolValue(value) -> json.bool(value)
    IntValue(value) -> json.int(value)
    FloatValue(value) -> json.float(value)
    ArrayValue(values) -> json.array(values, to_json)
    ObjectValue(values) -> json.dict(values, fn(key) { key }, to_json)
    NullValue -> json.null()
  }
}
