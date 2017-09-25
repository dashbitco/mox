# Mox

Mox is a tiny library for defining mocks in Elixir.

The library follows the principles outlined in ["Mocks and explicit contracts"](http://blog.plataformatec.com.br/2015/10/mocks-and-explicit-contracts/), summarized below:

  1. No ad-hoc mocks. You can only create mocks based on behaviours.

  2. No dynamic generation of modules during tests. Mocks defined by Mox
     are preferably defined in your `test_helper.exs` or in a `setup_all`
     block and not per test.

  3. They support concurrency (tests can still use `async: true`)

  4. Rely on pattern matching and function clauses for asserting on the
     input instead of complex mock rules

[See the documentation](https://hexdocs.pm/mox) for more information.

## Installation

Just add `mox` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:mox, "~> 0.1.0"}
  ]
end
```

## License

Copyright 2017 Plataformatec

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

      http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.

