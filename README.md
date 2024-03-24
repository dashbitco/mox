# Mox

[![Hex.pm](https://img.shields.io/hexpm/v/mox.svg?style=flat-square)](https://hex.pm/packages/mox)
[![Coverage Status](https://coveralls.io/repos/github/dashbitco/mox/badge.svg?branch=main)](https://coveralls.io/github/dashbitco/mox?branch=main)

Mox is a library for defining concurrent mocks in Elixir.

The library follows the principles outlined in ["Mocks and explicit contracts"](https://dashbit.co/blog/mocks-and-explicit-contracts), summarized below:

  1. No ad-hoc mocks. You can only create mocks based on behaviours

  2. No dynamic generation of modules during tests. Mocks are preferably defined in your `test_helper.exs` or in a `setup_all` block and not per test

  3. Concurrency support. Tests using the same mock can still use `async: true`

  4. Rely on pattern matching and function clauses for asserting on the
     input instead of complex expectation rules

The goal behind Mox is to help you think and define the contract between the different parts of your application. In the opinion of Mox maintainers, as long as you follow those guidelines and keep your tests concurrent, any library for mocks may be used (or, in certain cases, you may not even need one).

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

## Basic Usage

### 1) Add behaviour, defining the contract

```elixir
# lib/weather_behaviour.ex
defmodule WeatherBehaviour do
  @callback get_weather(binary()) :: {:ok, map()} | {:error, binary()}
end
```

### 2) Add implementation for the behaviour

```elixir
# lib/weather_impl.ex
defmodule WeatherImpl do
  @moduledoc """
  An implementation of a WeatherBehaviour
  """

  @behaviour WeatherBehaviour

  @impl WeatherBehaviour
  def get_weather(city) when is_binary(city) do
    # Here you could call an external api directly with an HTTP client or use a third
    # party library that does that work for you. In this example we send a
    # request using a `httpc` to get back some html, which we can process later.

    :inets.start()
    :ssl.start()

    case :httpc.request(:get, {"https://www.google.com/search?q=weather+#{city}", []}, [], []) do
      {:ok, {_, _, html_content}} -> {:ok, %{body: html_content}}
      error -> {:error, "Error getting weather: #{inspect(error)}"}
    end
  end
end
```

### 3) Add a switch

This can pull from your `config/config.exs`, `config/test.exs`, or, you can have no config as shown below and rely on a default. We also add a function to a higher level abstraction that will call the correct implementation:

```elixir
# bound.ex, the main context we chose to call this function from
defmodule Bound do
  def get_weather(city) do
    weather_impl().get_weather(city)
  end

  defp weather_impl() do
    Application.get_env(:bound, :weather, WeatherImpl)
  end
end
```

### 4) Define the mock so it is used during tests

```elixir
# In your test/test_helper.exs
Mox.defmock(WeatherBehaviourMock, for: WeatherBehaviour) # <- Add this
Application.put_env(:bound, :weather, WeatherBehaviourMock) # <- Add this

ExUnit.start()
```

### 5) Create a test and use `expect` to assert on the mock arguments

```elixir
# test/bound_test.exs
defmodule BoundTest do
  use ExUnit.Case

  import Mox

  setup :verify_on_exit!

  describe "get_weather/1" do
    test "fetches weather based on a location" do
      expect(WeatherBehaviourMock, :get_weather, fn args ->
        # here we can assert on the arguments that get passed to the function
        assert args == "Chicago"

        # here we decide what the mock returns
        {:ok, %{body: "Some html with weather data"}}
      end)

      assert {:ok, _} = Bound.get_weather("Chicago")
    end
  end
end
```

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
