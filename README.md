# supa

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
import midas/browser

pub type User {
  User(id: String, name: String, email: String)
}

fn user_decoder() {
  use id <- decode.field("id", decode.string)
  use name <- decode.field("name", decode.string)
  use email <- decode.field("email", decode.string)
  decode.success(User(id, name, email))
}

pub fn get_users() {
  let client = client.create("xyzcompany.supabase.co", "public-anon-key")

  // Select all users
  let query = database.from("users")

  browser.run(database.execute_select(client, query, user_decoder(), fn(result) {
    case result {
      Ok(users) -> // Handle list of users
      Error(_) -> // Handle error
    }
  }))
}

// Select with filters and ordering
pub fn get_active_users() {
  let client = client.create("xyzcompany.supabase.co", "public-anon-key")

  let query =
    database.from("users")
    |> database.select(["id", "name", "email"])
    |> database.filter(database.eq("status", "active"))
    |> database.order(database.desc("created_at"))
    |> database.limit(10)

  browser.run(database.execute_select(client, query, user_decoder(), handle_users))
}
```

### Inserting Data

```gleam
import gleam/json

pub fn create_user() {
  let client = client.create("xyzcompany.supabase.co", "public-anon-key")

  let user_data = json.object([
    #("name", json.string("John Doe")),
    #("email", json.string("john@example.com")),
    #("status", json.string("active"))
  ])

  browser.run(database.execute_insert(client, "users", user_data, fn(result) {
    case result {
      Ok(created_users) -> // Handle created user data
      Error(_) -> // Handle error
    }
  }))
}
```

### Updating Data

```gleam
pub fn update_user_status() {
  let client = client.create("xyzcompany.supabase.co", "public-anon-key")

  let query =
    database.from("users")
    |> database.filter(database.eq("id", "user-123"))

  let update_data = json.object([
    #("status", json.string("inactive"))
  ])

  browser.run(database.execute_update(client, query, update_data, handle_update))
}
```

### Deleting Data

```gleam
pub fn delete_user() {
  let client = client.create("xyzcompany.supabase.co", "public-anon-key")

  let query =
    database.from("users")
    |> database.filter(database.eq("id", "user-123"))

  browser.run(database.execute_delete(client, query, handle_delete))
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
