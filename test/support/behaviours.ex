defmodule Calculator do
  @callback add(integer(), integer()) :: integer()
  @callback mult(integer(), integer()) :: integer()
end

defmodule ScientificCalculator do
  @callback exponent(integer(), integer()) :: integer()
  @callback sin(integer()) :: float()
  @optional_callbacks [sin: 1]
end
