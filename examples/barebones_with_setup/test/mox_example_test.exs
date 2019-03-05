defmodule MoxExampleTest do
  import Mox

  use ExUnit.Case
  doctest MoxExample

  setup :verify_on_exit!

  test "posts name" do
    name = "Jim"
    ExampleAPIMock |>
			expect(:api_post, fn ^name, [], [] -> {:ok, nil} end)

		assert MoxExample.post_name(name) == {:ok, nil}
  end
end
