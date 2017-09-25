defmodule MoxTest do
  use ExUnit.Case, async: true

  import Mox
  doctest Mox

  defmodule Calculator do
    @callback add(integer(), integer()) :: integer()
    @callback mult(integer(), integer()) :: integer()
  end

  defmock CalcMock, for: Calculator

  describe "defmock/2" do
    test "raises for unknown module" do
      assert_raise ArgumentError, ~r"module Unknown is not available", fn ->
        defmock MyMock, for: Unknown
      end
    end

    test "raises for non behaviour" do
      assert_raise ArgumentError, ~r"module String is not a behaviour", fn ->
        defmock MyMock, for: String
      end
    end
  end

  describe "expect/4" do
    test "is invoked n times" do
      CalcMock
      |> expect(:add, 2, fn x, y -> x + y end)
      |> expect(:mult, fn x, y -> x * y end)
      |> expect(:add, fn _, _ -> 0 end)

      assert CalcMock.add(2, 3) == 5
      assert CalcMock.add(3, 2) == 5
      assert CalcMock.add(:whatever, :whatever) == 0
      assert CalcMock.mult(3, 2) == 6
    end

    test "can be recharged" do
      expect(CalcMock, :add, fn x, y -> x + y end)
      assert CalcMock.add(2, 3) == 5

      expect(CalcMock, :add, fn x, y -> x + y end)
      assert CalcMock.add(3, 2) == 5
    end

    test "raises if a non-mock is given" do
      assert_raise ArgumentError, ~r"module Unknown is not available", fn ->
        expect(Unknown, :add, fn x, y -> x + y end)
      end

      assert_raise ArgumentError, ~r"module String is not a mock", fn ->
        expect(String, :add, fn x, y -> x + y end)
      end
    end

    test "raises if function is not in behaviour" do
      assert_raise ArgumentError, ~r"unknown function oops/2 for mock CalcMock", fn ->
        expect(CalcMock, :oops, fn x, y -> x + y end)
      end

      assert_raise ArgumentError, ~r"unknown function add/3 for mock CalcMock", fn ->
        expect(CalcMock, :add, fn x, y, z -> x + y + z end)
      end
    end

    test "raises if there is no expectation" do
      assert_raise Mox.UnexpectedCallError, ~r"no expectation defined for CalcMock\.add/2", fn ->
        CalcMock.add(2, 3) == 5
      end
    end

    test "raises if all expectations are consumed" do
      expect(CalcMock, :add, fn x, y -> x + y end)
      assert CalcMock.add(2, 3) == 5

      assert_raise Mox.UnexpectedCallError, ~r"expected CalcMock.add/2 to be called once", fn ->
        CalcMock.add(2, 3) == 5
      end

      expect(CalcMock, :add, fn x, y -> x + y end)
      assert CalcMock.add(2, 3) == 5

      assert_raise Mox.UnexpectedCallError, ~r"expected CalcMock.add/2 to be called 2 times", fn ->
        CalcMock.add(2, 3) == 5
      end
    end
  end

  describe "verify!/0" do
    test "verifies all mocks for the current process" do
      verify!()
      expect(CalcMock, :add, fn x, y -> x + y end)

      message = ~r"expected CalcMock.add/2 to be invoked once but it was invoked 0 times"
      assert_raise Mox.VerificationError, message, &verify!/0

      assert CalcMock.add(2, 3) == 5
      verify!()
      expect(CalcMock, :add, fn x, y -> x + y end)

      message = ~r"expected CalcMock.add/2 to be invoked 2 times but it was invoked once"
      assert_raise Mox.VerificationError, message, &verify!/0
    end
  end

  describe "verify!/1" do
    test "verifies all mocks for the current process" do
      verify!(CalcMock)
      expect(CalcMock, :add, fn x, y -> x + y end)

      message = ~r"expected CalcMock.add/2 to be invoked once but it was invoked 0 times"
      assert_raise Mox.VerificationError, message, &verify!/0

      assert CalcMock.add(2, 3) == 5
      verify!(CalcMock)
      expect(CalcMock, :add, fn x, y -> x + y end)

      message = ~r"expected CalcMock.add/2 to be invoked 2 times but it was invoked once"
      assert_raise Mox.VerificationError, message, &verify!/0
    end

    test "raises if a non-mock is given" do
      assert_raise ArgumentError, ~r"module Unknown is not available", fn ->
        verify!(Unknown)
      end

      assert_raise ArgumentError, ~r"module String is not a mock", fn ->
        verify!(String)
      end
    end
  end
end
