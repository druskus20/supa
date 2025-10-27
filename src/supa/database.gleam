import gleam/dynamic/decode
import gleam/dynamic
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import rsvp
import supa/client


pub type Query {
  Query(
    table: String,
    select_columns: List(String),
    filters: List(Filter),
    orders: List(Order),
    limit_value: option.Option(Int),
    offset_value: option.Option(Int),
  )
}

pub type Filter {
  Eq(column: String, value: String)
  Neq(column: String, value: String)
  Gt(column: String, value: String)
  Gte(column: String, value: String)
  Lt(column: String, value: String)
  Lte(column: String, value: String)
  Like(column: String, pattern: String)
  Ilike(column: String, pattern: String)
  In(column: String, values: List(String))
  IsNull(column: String)
  Not(filter: Filter)
}

pub type Order {
  Asc(column: String)
  Desc(column: String)
}

pub type DatabaseResult(a) {
  DatabaseResult(data: List(a), count: option.Option(Int))
}

fn base_request(client: client.Client) {
  let client.Client(host, key) = client
  request.new()
  |> request.set_host(host)
  |> request.prepend_header("apikey", key)
  |> request.prepend_header("Content-Type", "application/json")
  |> request.set_path("/rest/v1")
}

fn authenticated_request(client: client.Client, access_token: String) {
  let client.Client(host, api_key) = client
  request.new()
  |> request.set_host(host)
  |> request.prepend_header("apikey", api_key)
  |> request.prepend_header("Authorization", "Bearer " <> access_token)
  |> request.prepend_header("Content-Type", "application/json")
  |> request.set_path("/rest/v1")
}

fn make_request(client: client.Client, access_token: option.Option(String)) {
  case access_token {
    None -> base_request(client)
    Some(token) -> authenticated_request(client, token)
  }
}

pub fn from(table: String) -> Query {
  Query(
    table: table,
    select_columns: ["*"],
    filters: [],
    orders: [],
    limit_value: None,
    offset_value: None,
  )
}

pub fn select(query: Query, columns: List(String)) -> Query {
  Query(..query, select_columns: columns)
}

fn filter_to_string(filter: Filter) -> String {
  case filter {
    Eq(column, value) -> column <> "=eq." <> value
    Neq(column, value) -> column <> "=neq." <> value
    Gt(column, value) -> column <> "=gt." <> value
    Gte(column, value) -> column <> "=gte." <> value
    Lt(column, value) -> column <> "=lt." <> value
    Lte(column, value) -> column <> "=lte." <> value
    Like(column, pattern) -> column <> "=like." <> pattern
    Ilike(column, pattern) -> column <> "=ilike." <> pattern
    In(column, values) -> column <> "=in.(" <> string.join(values, ",") <> ")"
    IsNull(column) -> column <> "=is.null"
    Not(inner_filter) -> "not.(" <> filter_to_string(inner_filter) <> ")"
  }
}

fn order_to_string(order: Order) -> String {
  case order {
    Asc(column) -> column
    Desc(column) -> column <> ".desc"
  }
}

fn build_query_string(query: Query) -> String {
  let select_param = "select=" <> string.join(query.select_columns, ",")

  let filter_strings = case query.filters {
    [] -> []
    filters -> list.map(filters, filter_to_string)
  }

  let order_string = case query.orders {
    [] -> []
    orders -> ["order=" <> string.join(list.map(orders, order_to_string), ",")]
  }

  let limit_string = case query.limit_value {
    None -> []
    Some(limit) -> ["limit=" <> int.to_string(limit)]
  }

  let offset_string = case query.offset_value {
    None -> []
    Some(offset) -> ["offset=" <> int.to_string(offset)]
  }

  [select_param]
  |> list.append(filter_strings)
  |> list.append(order_string)
  |> list.append(limit_string)
  |> list.append(offset_string)
  |> string.join("&")
}

pub fn execute_select(client: client.Client, access_token: option.Option(String), query: Query, decoder: decode.Decoder(a), handler: fn(Result(List(a), rsvp.Error)) -> b) {
  let query_string = build_query_string(query)
  let path = "/rest/v1/" <> query.table <> "?" <> query_string

  let request =
    make_request(client, access_token)
    |> request.set_method(http.Get)
    |> request.set_path(path)

  rsvp.send(
    request,
    rsvp.expect_any_response(decode_database_response(_, decode.list(decoder), handler)),
  )
}

pub fn execute_select_single(client: client.Client, access_token: option.Option(String), query: Query, decoder: decode.Decoder(a), handler: fn(Result(option.Option(a), rsvp.Error)) -> b) {
  let limited_query = limit(query, 1)
  execute_select(client, access_token, limited_query, decoder, fn(result) {
    case result {
      Ok([item]) -> handler(Ok(Some(item)))
      Ok([]) -> handler(Ok(None))
      Ok(_) -> handler(Ok(None))
      Error(err) -> handler(Error(err))
    }
  })
}

fn decode_database_response(
  response: Result(response.Response(String), rsvp.Error),
  decoder: decode.Decoder(a),
  handler: fn(Result(a, rsvp.Error)) -> b,
) -> b {
  case response {
    Ok(response) -> {
      case response.status {
        code if code >= 200 && code < 300 -> {
          case response.get_header(response, "content-type") {
            Ok("application/json") | Ok("application/json;" <> _) -> {
              case json.parse(response.body, decoder) {
                Ok(data) -> handler(Ok(data))
                Error(decode_error) -> handler(Error(rsvp.JsonError(decode_error)))
              }
            }
            _ -> handler(Error(rsvp.UnhandledResponse(response)))
          }
        }
        code if code >= 400 && code < 600 -> {
          handler(Error(rsvp.HttpError(response)))
        }
        _ -> {
          handler(Error(rsvp.UnhandledResponse(response)))
        }
      }
    }
    Error(rsvp_error) -> handler(Error(rsvp_error))
  }
}

pub fn execute_insert(client: client.Client, access_token: option.Option(String), table: String, data: json.Json, handler: fn(Result(List(dynamic.Dynamic), rsvp.Error)) -> a) {
  let path = "/rest/v1/" <> table

  let request =
    make_request(client, access_token)
    |> request.set_method(http.Post)
    |> request.set_path(path)
    |> request.prepend_header("Prefer", "return=representation")
    |> request.set_body(json.to_string(data))

  rsvp.send(
    request,
    rsvp.expect_any_response(decode_database_response(_, decode.list(decode.dynamic), handler)),
  )
}

pub fn execute_insert_batch(client: client.Client, access_token: option.Option(String), table: String, data: List(json.Json), handler: fn(Result(List(dynamic.Dynamic), rsvp.Error)) -> a) {
  let json_array = json.array(data, fn(x) { x })
  execute_insert(client, access_token, table, json_array, handler)
}

pub fn execute_upsert(client: client.Client, access_token: option.Option(String), table: String, data: json.Json, handler: fn(Result(List(dynamic.Dynamic), rsvp.Error)) -> a) {
  let path = "/rest/v1/" <> table

  let request =
    make_request(client, access_token)
    |> request.set_method(http.Post)
    |> request.set_path(path)
    |> request.prepend_header("Prefer", "return=representation,resolution=merge-duplicates")
    |> request.set_body(json.to_string(data))

  rsvp.send(
    request,
    rsvp.expect_any_response(decode_database_response(_, decode.list(decode.dynamic), handler)),
  )
}

pub fn execute_update(client: client.Client, access_token: option.Option(String), query: Query, data: json.Json, handler: fn(Result(List(dynamic.Dynamic), rsvp.Error)) -> a) {
  let filter_strings = case query.filters {
    [] -> ""
    filters -> "?" <> string.join(list.map(filters, filter_to_string), "&")
  }

  let path = "/rest/v1/" <> query.table <> filter_strings

  let request =
    make_request(client, access_token)
    |> request.set_method(http.Patch)
    |> request.set_path(path)
    |> request.prepend_header("Prefer", "return=representation")
    |> request.set_body(json.to_string(data))

  rsvp.send(
    request,
    rsvp.expect_any_response(decode_database_response(_, decode.list(decode.dynamic), handler)),
  )
}

pub fn execute_delete(client: client.Client, access_token: option.Option(String), query: Query, handler: fn(Result(List(dynamic.Dynamic), rsvp.Error)) -> a) {
  let filter_strings = case query.filters {
    [] -> ""
    filters -> "?" <> string.join(list.map(filters, filter_to_string), "&")
  }

  let path = "/rest/v1/" <> query.table <> filter_strings

  let request =
    make_request(client, access_token)
    |> request.set_method(http.Delete)
    |> request.set_path(path)
    |> request.prepend_header("Prefer", "return=representation")

  rsvp.send(
    request,
    rsvp.expect_any_response(decode_database_response(_, decode.list(decode.dynamic), handler)),
  )
}

pub fn eq(column: String, value: String) -> Filter {
  Eq(column, value)
}

pub fn neq(column: String, value: String) -> Filter {
  Neq(column, value)
}

pub fn gt(column: String, value: String) -> Filter {
  Gt(column, value)
}

pub fn gte(column: String, value: String) -> Filter {
  Gte(column, value)
}

pub fn lt(column: String, value: String) -> Filter {
  Lt(column, value)
}

pub fn lte(column: String, value: String) -> Filter {
  Lte(column, value)
}

pub fn like(column: String, pattern: String) -> Filter {
  Like(column, pattern)
}

pub fn ilike(column: String, pattern: String) -> Filter {
  Ilike(column, pattern)
}

pub fn in_(column: String, values: List(String)) -> Filter {
  In(column, values)
}

pub fn is_null(column: String) -> Filter {
  IsNull(column)
}

pub fn not_(filter: Filter) -> Filter {
  Not(filter)
}

pub fn filter(query: Query, new_filter: Filter) -> Query {
  Query(..query, filters: list.append(query.filters, [new_filter]))
}

pub fn order(query: Query, new_order: Order) -> Query {
  Query(..query, orders: list.append(query.orders, [new_order]))
}

pub fn limit(query: Query, count: Int) -> Query {
  Query(..query, limit_value: Some(count))
}

pub fn offset(query: Query, count: Int) -> Query {
  Query(..query, offset_value: Some(count))
}

pub fn asc(column: String) -> Order {
  Asc(column)
}

pub fn desc(column: String) -> Order {
  Desc(column)
}