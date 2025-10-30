// API page list best all the endpoints https://supabase.com/dashboard/project/wrdiolbafudgmcgvqhnb/api?page=users
import gleam/dynamic/decode
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/json
import gleam/pair
import rsvp
import supa/client
import supa/utils

fn base(client) {
  let client.Client(host, key) = client
  request.new()
  |> request.set_host(host)
  |> request.prepend_header("apikey", key)
  |> request.set_path("/auth/v1")
  // Authorization header needed for auth endpoint
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
    dispatch(handler(parse_url_session()))
  })
}

@external(javascript, "./auth_ffi.mjs", "parseUrlSession")
fn parse_url_session() -> Result(#(Session, User), Nil)

pub fn oauth_url_decoder() {
  use url <- decode.field("url", decode.string)
  decode.success(url)
}

pub fn verify_decoder() {
  use session <- decode.field("session", session_decoder())
  use user <- decode.field("user", user_decoder())
  decode.success(pair.new(session, user))
}

// useful for storage
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
          // Check content type for JSON
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
