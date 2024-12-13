# supa

[Supabase](https://supabase.com/) client implemented in Gleam. 

Notes:
1. Doesn't build on any supabase.js libraries so it can be used on the frontend and BEAM backends
1. Currently only auth is implemented but contributes welcome

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

Further documentation can be found at <https://hexdocs.pm/supa>.

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
```

## Credit

Created for [EYG](https://eyg.run/), a new integration focused programming language.