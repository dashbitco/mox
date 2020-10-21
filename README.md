# Mox

[![Hex.pm](https://img.shields.io/hexpm/v/mox.svg?style=flat-square)](https://hex.pm/packages/mox)

Mox is a library for defining concurrent mocks in Elixir.

The library follows the principles outlined in ["Mocks and explicit contracts"](https://dashbit.co/blog/mocks-and-explicit-contracts), summarized below:

  1. No ad-hoc mocks. You can only create mocks based on behaviours

  2. No dynamic generation of modules during tests. Mocks are preferably defined in your `test_helper.exs` or in a `setup_all` block and not per test

  3. Concurrency support. Tests using the same mock can still use `async: true`

  4. Rely on pattern matching and function clauses for asserting on the
     input instead of complex expectation rules

[See the documentation](https://hexdocs.pm/mox) for more information.

## Installation

Just add `mox` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:mox, "~> 1.0", only: :test}
  ]
end
```

Mox should be automatically started unless the `:applications` key is set inside `def application` in your `mix.exs`. In such cases, you need to [remove the `:applications` key in favor of `:extra_applications`](https://elixir-lang.org/blog/2017/01/05/elixir-v1-4-0-released/#application-inference) or call `Application.ensure_all_started(:mox)` in your `test/test_helper.exs`.

## Enforcing consistency with behaviour typespecs

[Hammox](https://github.com/msz/hammox) is an enhanced version of Mox which automatically makes sure that calls to mocks match the typespecs defined in the behaviour. If you find this useful, see the [project homepage](https://github.com/msz/hammox).

## License

Copyright 2017 Plataformatec \
Copyright 2020 Dashbit

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

      http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.
