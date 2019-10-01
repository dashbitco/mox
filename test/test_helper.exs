excludes =
  [
    {"< 1.7.0", [:requires_code_fetch_docs]},
    {"< 1.8.0", [:requires_caller_tracking]}
  ]
  |> Enum.flat_map(fn {version, tags} ->
    if Version.match?(System.version(), version), do: tags, else: []
  end)

ExUnit.start(exclude: excludes)
