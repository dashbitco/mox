defmodule CalculatorWithStruct do
  @behaviour Calculator
  @behaviour ScientificCalculator
  def add(a, b), do: a + b
  def mult(a, b), do: a * b
  def exponent(a, b), do: a - b
  def sin(a), do: a * 1.0
  defstruct [ans: 0]
end

defmodule CalculatorStructOneBehaviour do
  @behaviour Calculator
  def add(a, b), do: a + b
  def mult(a, b), do: a * b
  defstruct [ans: 0]
end

defmodule CalculatorNoStruct do
  @behaviour Calculator
  def add(a, b), do: a + b
  def mult(a, b), do: a * b
end
