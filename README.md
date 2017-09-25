# Mox

Mox is a library for defining mocks in Elixir.

The library follows the principles outlined in ["Mocks and explicit contracts"](http://blog.plataformatec.com.br/2015/10/mocks-and-explicit-contracts/), summarized below:

  1. No ad-hoc mocks. You can only create mocks based on behaviours.

  2. No dynamic generation of modules during tests. Mocks defined by Mox
     are preferably defined in your `test_helper.exs` or in a `setup_all`
     block and not per test.

  3. They support concurrency (tests can still use `async: true`)

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

The same License as Elixir.
