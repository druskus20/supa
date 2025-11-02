# supa

> [!WARN] 
> This is a fork of the original supa library by CrowdHailer: https://github.com/CrowdHailer/supa. 
> I recommend using that version since I am unsure how actively this fork will
> be maintained (if at all).

[Supabase](https://supabase.com/) client implemented in Gleam. 

Notes:
1. Doesn't build on any supabase.js libraries so it can be used on the frontend and BEAM backends
1. Includes auth and database functions for complete frontend data access

[![Package Version](https://img.shields.io/hexpm/v/supa)](https://hex.pm/packages/supa)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/supa/)

```sh
gleam add supa@1
```
## Using Authentication

Example shows magic link authentication. As this is probably running in the browser it uses `midas_browser` to run the task.

```gleam
import supa/auth
import supa/client
import midas/browser
import gleam/javascript/promise

pub fn main() {
  // using the anon-key allows means this client can safely be used in the browser.
  let client =  client.create("xyzcompany.supabase.co", "public-anon-key")
  let email = "me@example.com"
  use result <- promise.try_await(browser.run(auth.sign_in_with_otp(client, email, True)))

  let code = todo
  // get user to enter code
  use #(session, user) <- promise.try_await(browser.run(auth.verify_otp(client, email, code)))
  // save or use the session
}
```

## Using Database Functions

The database module provides functions for querying, inserting, updating, and deleting data from your Supabase database.

### Querying Data

```gleam
import supa/database
import supa/client
import gleam/dynamic/decode
import gleam/option.{Some}
import lustre/effect

pub type User {
  User(id: String, name: String, email: String)
}

fn user_decoder() {
  use id <- decode.field("id", decode.string)
  use name <- decode.field("name", decode.string)
  use email <- decode.field("email", decode.string)
  decode.success(User(id, name, email))
}

pub fn list_users(client: client.Client, access_token: String) -> effect.Effect(Result(List(User), String)) {
  let query = database.from("users")

  database.execute_select(
    client,
    Some(access_token),
    query,
    user_decoder(),
    fn(result) {
      case result {
        Ok(users) -> Ok(users)
        Error(_) -> Error("Failed to fetch users")
      }
    },
  )
}

// Select with filters and ordering
pub fn get_active_users(client: client.Client, access_token: String) -> effect.Effect(Result(List(User), String)) {
  let query =
    database.from("users")
    |> database.filter(database.eq("status", "active"))
    |> database.order(database.desc("created_at"))
    |> database.limit(10)

  database.execute_select(
    client,
    Some(access_token),
    query,
    user_decoder(),
    fn(result) {
      case result {
        Ok(users) -> Ok(users)
        Error(_) -> Error("Failed to fetch users")
      }
    },
  )
}
```

### Inserting Data

```gleam
import gleam/json

pub fn create_user(
  client: client.Client,
  access_token: String,
  name: String,
  email: String
) -> effect.Effect(Result(User, String)) {
  let user_data = json.object([
    #("name", json.string(name)),
    #("email", json.string(email)),
    #("status", json.string("active"))
  ])

  database.execute_insert(
    client,
    Some(access_token),
    "users",
    user_data,
    fn(result) {
      case result {
        Ok([dynamic_user]) -> {
          case decode.run(dynamic_user, user_decoder()) {
            Ok(new_user) -> Ok(new_user)
            Error(_) -> Error("Failed to parse created user")
          }
        }
        Ok(_) -> Error("Unexpected response from create")
        Error(_) -> Error("Failed to create user")
      }
    },
  )
}
```

### Updating Data

```gleam
pub fn update_user_status(
  client: client.Client,
  access_token: String,
  user_id: String,
  status: String
) -> effect.Effect(Result(User, String)) {
  let query =
    database.from("users")
    |> database.filter(database.eq("id", user_id))

  let update_data = json.object([
    #("status", json.string(status))
  ])

  database.execute_update(
    client,
    Some(access_token),
    query,
    update_data,
    fn(result) {
      case result {
        Ok([dynamic_user]) -> {
          case decode.run(dynamic_user, user_decoder()) {
            Ok(updated_user) -> Ok(updated_user)
            Error(_) -> Error("Failed to parse updated user")
          }
        }
        Ok([]) -> Error("User not found for update")
        Ok(_) -> Error("Multiple users returned from update")
        Error(_) -> Error("Failed to update user")
      }
    },
  )
}
```

### Deleting Data

```gleam
pub fn delete_user(
  client: client.Client,
  access_token: String,
  user_id: String
) -> effect.Effect(Result(Nil, String)) {
  let query =
    database.from("users")
    |> database.filter(database.eq("id", user_id))

  database.execute_delete(
    client,
    Some(access_token),
    query,
    fn(result) {
      case result {
        Ok(_) -> Ok(Nil)
        Error(_) -> Error("Failed to delete user")
      }
    }
  )
}
```

Further documentation can be found at <https://hexdocs.pm/supa>.

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
```

## Credit

Created for [EYG](https://eyg.run/), a new integration focused programming language.
