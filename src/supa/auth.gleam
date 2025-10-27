import gleam/dynamic/decode
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/json
import gleam/pair
import gleam/option.{None, Some}
import gleam/string
import rsvp
import supa/client
import supa/utils

fn base(client) {
  let client.Client(host, key) = client
  request.new()
  |> request.set_host(host)
  |> request.prepend_header("apikey", key)
  |> request.set_path("/auth/v1")
  |> request.prepend_header("Authorization", "Bearer " <> key)
  |> request.set_body("")
}

pub fn sign_in_with_otp(client, email_address, create_user, handler) {
  let request =
    base(client)
    |> request.set_method(http.Post)
    |> utils.append_path("/otp")
    |> request.set_body(
      json.to_string(
        json.object([
          #("email", json.string(email_address)),
          #("create_user", json.bool(create_user)),
        ]),
      ),
    )
  rsvp.send(
    request,
    rsvp.expect_any_response(decode_response(_, decode.success(Nil), handler)),
  )
}

pub fn verify_otp(client, email_address, token, handler) {
  let request =
    base(client)
    |> request.set_method(http.Post)
    |> utils.append_path("/verify")
    |> request.set_body(
      json.to_string(
        json.object([
          #("email", json.string(email_address)),
          #("token", json.string(token)),
          #("type", json.string("magiclink")),
        ]),
      ),
    )
  rsvp.send(
    request,
    rsvp.expect_any_response(decode_response(_, verify_decoder(), handler)),
  )
}

pub fn sign_in_with_github(client, redirect_to, effect_from, handler) {
  let client.Client(host, _) = client
  let auth_url = "https://" <> host <> "/auth/v1/authorize?provider=github&redirect_to=" <> redirect_to
  effect_from(fn(dispatch) { dispatch(handler(Ok(auth_url))) })
}

pub fn exchange_code_for_session(client, authorization_code, code_verifier, handler) {
  let request =
    base(client)
    |> request.set_method(http.Post)
    |> utils.append_path("/token")
    |> request.set_body(
      json.to_string(
        json.object([
          #("grant_type", json.string("authorization_code")),
          #("code", json.string(authorization_code)),
          #("code_verifier", json.string(code_verifier)),
        ]),
      ),
    )
  rsvp.send(
    request,
    rsvp.expect_any_response(decode_response(_, verify_decoder(), handler)),
  )
}

pub fn get_session_from_url(effect_from, handler) {
  effect_from(fn(dispatch) {
    let result = parse_session()
    dispatch(handler(result))
  })
}

pub fn sign_out(
  client: client.Client,
  handler: fn(Result(Nil, rsvp.Error)) -> a,
) -> Nil {
  case get_stored_session() {
    Ok(json_str) -> {
      case json.parse(json_str, stored_session_decoder()) {
        Ok(#(session, _)) -> {
          let _ = clear_session()

          let _ = handler(Ok(Nil))

          let request =
            base(client)
            |> request.set_method(http.Post)
            |> request.prepend_header("Authorization", "Bearer " <> session.access_token)
            |> utils.append_path("/logout")
          let _ = rsvp.send(
            request,
            rsvp.expect_any_response(decode_response(_, decode.success(Nil), fn(result) {
            })),
          )
          Nil
        }
        Error(_) -> {
          let _ = clear_session()
          let _ = handler(Ok(Nil))
          Nil
        }
      }
    }
    Error(_) -> {
      let _ = clear_session()
      let _ = handler(Ok(Nil))
      Nil
    }
  }
}

fn parse_session() -> Result(#(Session, User), String) {
  let fragment = get_url_fragment()

  case fragment {
    "" -> {
      parse_stored_session()
    }
    _ -> {
      case parse_oauth_fragment(fragment) {
        Ok(session_user) -> {
          let #(session, user) = session_user
          let _ = store_session_data(session, user)
          let _ = clear_url_fragment()
          Ok(session_user)
        }
        Error(err) -> Error(err)
      }
    }
  }
}

fn parse_stored_session() -> Result(#(Session, User), String) {
  case get_stored_session() {
    Ok(json_str) -> {
      case json.parse(json_str, stored_session_decoder()) {
        Ok(session_user) -> {
          let #(session, _user) = session_user
          let current_time = get_current_time()
          case session.expires_at > current_time {
            True -> {
              Ok(session_user)
            }
            False -> {
              let _ = clear_session()
              Error("Session expired")
            }
          }
        }
        Error(_) -> {
          let _ = clear_session()
          Error("Invalid stored session")
        }
      }
    }
    Error(_) -> {
      Error("No stored session")
    }
  }
}

fn parse_oauth_fragment(fragment: String) -> Result(#(Session, User), String) {
  case utils.parse_url_params(fragment) {
    Ok(params) -> {
      case utils.get_param(params, "access_token") {
        Some(access_token) -> {
          case parse_jwt_user(access_token) {
            Ok(user) -> {
              let session = Session(
                access_token: access_token,
                expires_at: get_current_time() + utils.get_param_int(params, "expires_in", 3600),
                expires_in: utils.get_param_int(params, "expires_in", 3600),
                refresh_token: case utils.get_param(params, "refresh_token") {
                  Some(token) -> token
                  None -> ""
                },
                token_type: case utils.get_param(params, "token_type") {
                  Some(type_) -> type_
                  None -> "bearer"
                },
              )
              Ok(#(session, user))
            }
            Error(err) -> Error("JWT parse error: " <> err)
          }
        }
        None -> Error("No access token in URL")
      }
    }
    Error(err) -> Error("URL parse error: " <> err)
  }
}

fn parse_jwt_user(token: String) -> Result(User, String) {
  case js_parse_jwt(token) {
    Ok(payload) -> {
      case json.parse(payload, jwt_user_decoder()) {
        Ok(user) -> Ok(user)
        Error(_) -> Error("Invalid JWT payload")
      }
    }
    Error(_) -> Error("JWT decode failed")
  }
}

fn store_session_data(session: Session, user: User) -> Nil {
  let json_data = verify_to_json(session, user) |> json.to_string
  store_session(json_data)
}

fn stored_session_decoder() {
  use access_token <- decode.field("access_token", decode.string)
  use expires_at <- decode.field("expires_at", decode.int)
  use expires_in <- decode.field("expires_in", decode.int)
  use refresh_token <- decode.field("refresh_token", decode.string)
  use token_type <- decode.field("token_type", decode.string)
  use user <- decode.field("user", user_decoder())

  let session = Session(access_token, expires_at, expires_in, refresh_token, token_type)
  decode.success(#(session, user))
}

fn jwt_user_decoder() {
  use id <- decode.field("sub", decode.string)
  use email <- decode.field("email", decode.string)
  decode.success(User(
    created_at: "2024-01-01T00:00:00Z", // JWT doesn't have created_at
    email: email,
    id: id,
  ))
}

@external(javascript, "./auth_ffi.mjs", "getUrlFragment")
fn get_url_fragment() -> String

@external(javascript, "./auth_ffi.mjs", "getStoredSession")
fn get_stored_session() -> Result(String, Nil)

@external(javascript, "./auth_ffi.mjs", "storeSession")
fn store_session(json: String) -> Nil

@external(javascript, "./auth_ffi.mjs", "getCurrentTime")
fn get_current_time() -> Int

@external(javascript, "./auth_ffi.mjs", "parseJwt")
fn js_parse_jwt(token: String) -> Result(String, Nil)

@external(javascript, "./auth_ffi.mjs", "clearUrlFragment")
fn clear_url_fragment() -> Nil

@external(javascript, "./auth_ffi.mjs", "clearSession")
fn clear_session() -> Nil

@external(javascript, "./auth_ffi.mjs", "debugLog")

fn debug_result(result: Result(#(Session, User), String)) -> String {
  case result {
    Ok(#(_session, user)) -> "Ok(session for " <> user.email <> ")"
    Error(msg) -> "Error(" <> msg <> ")"
  }
}

fn int_to_string(i: Int) -> String {
  int.to_string(i)
}

fn debug_sign_out_result(result: Result(Nil, rsvp.Error)) -> String {
  case result {
    Ok(_) -> "Ok(Nil)"
    Error(err) -> "Error(" <> string.inspect(err) <> ")"
  }
}

pub fn oauth_url_decoder() {
  use url <- decode.field("url", decode.string)
  decode.success(url)
}

pub fn verify_decoder() {
  use session <- decode.field("session", session_decoder())
  use user <- decode.field("user", user_decoder())
  decode.success(pair.new(session, user))
}

pub fn verify_to_json(session, user) {
  let User(created_at, email, id) = user
  let user =
    json.object([
      #("created_at", json.string(created_at)),
      #("email", json.string(email)),
      #("id", json.string(id)),
    ])
  let Session(access_token, expires_at, expires_in, refresh_token, token_type) =
    session
  json.object([
    #("access_token", json.string(access_token)),
    #("expires_at", json.int(expires_at)),
    #("expires_in", json.int(expires_in)),
    #("refresh_token", json.string(refresh_token)),
    #("token_type", json.string(token_type)),
    #("user", user),
  ])
}

pub type Session {
  Session(
    access_token: String,
    expires_at: Int,
    expires_in: Int,
    refresh_token: String,
    token_type: String,
  )
}

fn session_decoder() {
  use access_token <- decode.field("access_token", decode.string)
  use expires_at <- decode.field("expires_at", decode.int)
  use expires_in <- decode.field("expires_in", decode.int)
  use refresh_token <- decode.field("refresh_token", decode.string)
  use token_type <- decode.field("token_type", decode.string)
  decode.success(Session(
    access_token,
    expires_at,
    expires_in,
    refresh_token,
    token_type,
  ))
}

pub type User {
  User(created_at: String, email: String, id: String)
}

fn user_decoder() {
  use created_at <- decode.field("created_at", decode.string)
  use email <- decode.field("email", decode.string)
  use id <- decode.field("id", decode.string)
  decode.success(User(created_at, email, id))
}

fn decode_response(
  response: Result(response.Response(String), rsvp.Error),
  decoder,
  handler,
) {
  case response {
    Ok(response) ->
      case response.status {
        code if code >= 200 && code < 300 -> {
          case response.get_header(response, "content-type") {
            Ok("application/json") | Ok("application/json;" <> _) -> {
              case json.parse(response.body, decoder) {
                Ok(data) -> handler(Ok(data))
                Error(decode_error) ->
                  handler(Error(rsvp.JsonError(decode_error)))
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
    Error(rsvp_error) -> handler(Error(rsvp_error))
  }
}

pub type Reason {
  Reason(error: String, message: String)
}
