import gleam/http/request
import gleam/string
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/int

pub fn append_path(request, path) {
  request.set_path(request, request.path <> path)
}

pub fn parse_url_params(query_string: String) -> Result(List(#(String, String)), String) {
  case query_string {
    "" -> Ok([])
    _ -> {
      query_string
      |> string.split("&")
      |> list.try_map(fn(pair) {
        case string.split(pair, "=") {
          [key, value] -> Ok(#(key, value))
          [key] -> Ok(#(key, ""))
          _ -> Error("Invalid param: " <> pair)
        }
      })
    }
  }
}

pub fn get_param(params: List(#(String, String)), key: String) -> Option(String) {
  case list.find(params, fn(pair) { pair.0 == key }) {
    Ok(#(_, value)) -> Some(value)
    Error(_) -> None
  }
}

pub fn get_param_int(params: List(#(String, String)), key: String, default: Int) -> Int {
  case get_param(params, key) {
    Some(value) -> case int.parse(value) {
      Ok(parsed) -> parsed
      Error(_) -> default
    }
    None -> default
  }
}
