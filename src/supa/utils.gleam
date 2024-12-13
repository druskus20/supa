import gleam/http/request

pub fn append_path(request, path) {
  request.set_path(request, request.path <> path)
}
