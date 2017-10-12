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

  describe "verify_on_exit!/0" do
    setup :verify_on_exit!

    test "verifies all mocks even if none is used" do
      :ok
    end

    test "verifies all mocks for the current process on exit" do
      expect(CalcMock, :add, fn x, y -> x + y end)
      assert CalcMock.add(2, 3) == 5
    end

    test "verifies all mocks for the current process on exit with previous verification" do
      verify!()
      expect(CalcMock, :add, fn x, y -> x + y end)
      assert CalcMock.add(2, 3) == 5
    end
  end

  describe "stub/3" do
    test "allows repeated invocations" do
      stub(CalcMock, :add, fn x, y -> x + y end)
      assert CalcMock.add(1, 2) == 3
      assert CalcMock.add(3, 4) == 7
    end

    test "does not fail verification if not called" do
      stub(CalcMock, :add, fn x, y -> x + y end)
      verify!()
    end

    test "gives expected calls precedence" do
      CalcMock
      |> stub(:add, fn x, y -> x + y end)
      |> expect(:add, fn _, _ -> :expected end)
      assert CalcMock.add(1, 1) == :expected
      verify!()
    end

    test "invokes stub after expectations are fulfilled" do
      CalcMock
      |> stub(:add, fn _x, _y -> :stub end)
      |> expect(:add, 2, fn _, _ -> :expected end)
      assert CalcMock.add(1, 1) == :expected
      assert CalcMock.add(1, 1) == :expected
      assert CalcMock.add(1, 1) == :stub
      verify!()
    end

    test "overwrites earlier stubs" do
      CalcMock
      |> stub(:add, fn x, y -> x + y end)
      |> stub(:add, fn _x, _y -> 42 end)
      assert CalcMock.add(1, 1) == 42
    end

    test "raises if a non-mock is given" do
      assert_raise ArgumentError, ~r"module Unknown is not available", fn ->
        stub(Unknown, :add, fn x, y -> x + y end)
      end

      assert_raise ArgumentError, ~r"module String is not a mock", fn ->
        stub(String, :add, fn x, y -> x + y end)
      end
    end

    test "raises if function is not in behaviour" do
      assert_raise ArgumentError, ~r"unknown function oops/2 for mock CalcMock", fn ->
        stub(CalcMock, :oops, fn x, y -> x + y end)
      end

      assert_raise ArgumentError, ~r"unknown function add/3 for mock CalcMock", fn ->
        stub(CalcMock, :add, fn x, y, z -> x + y + z end)
      end
    end
  end

  describe "allow/3" do
    setup :verify_on_exit!

    test "allows different processes to share mocks from parent process" do
      parent_pid = self()

      {:ok, child_pid} =
        Task.start_link(fn ->
          assert_raise Mox.UnexpectedCallError, fn -> CalcMock.add(1, 1) end

          receive do
            :call_mock ->
              add_result = CalcMock.add(1, 1)
              mult_result = CalcMock.mult(1, 1)
              send(parent_pid, {:verify, add_result, mult_result})
          end
        end)

      CalcMock
      |> expect(:add, fn _, _ -> :expected end)
      |> stub(:mult, fn _, _ -> :stubbed end)
      |> allow(self(), child_pid)

      send(child_pid, :call_mock)

      assert_receive {:verify, add_result, mult_result}
      assert add_result == :expected
      assert mult_result == :stubbed
    end

    test "allows different processes to share mocks from child process" do
      parent_pid = self()

      CalcMock
      |> expect(:add, fn _, _ -> :expected end)
      |> stub(:mult, fn _, _ -> :stubbed end)

      Task.async(fn ->
        assert_raise Mox.UnexpectedCallError, fn -> CalcMock.add(1, 1) end

        CalcMock
        |> allow(parent_pid, self())

        assert CalcMock.add(1, 1) == :expected
        assert CalcMock.mult(1, 1) == :stubbed
      end) |> Task.await()
    end

    test "allowances are transitive" do
      parent_pid = self()

      {:ok, child_pid} =
        Task.start_link(fn ->
          assert_raise Mox.UnexpectedCallError, fn -> CalcMock.add(1, 1) end
          receive do
            :call_mock ->
              add_result = CalcMock.add(1, 1)
              mult_result = CalcMock.mult(1, 1)
              send(parent_pid, {:verify, add_result, mult_result})
          end
        end)

      {:ok, transitive_pid} =
        Task.start_link(fn ->
          receive do
            :allow_mock ->
              CalcMock
              |> allow(self(), child_pid)
              send(child_pid, :call_mock)
          end
        end)

      CalcMock
      |> expect(:add, fn _, _ -> :expected end)
      |> stub(:mult, fn _, _ -> :stubbed end)
      |> allow(self(), transitive_pid)

      send(transitive_pid, :allow_mock)

      receive do
        {:verify, add_result, mult_result} ->
          assert add_result == :expected
          assert mult_result == :stubbed
          verify!()
      after
        1000 -> verify!()
      end
    end

    test "allowances are reclaimed if the owner process dies" do
      parent_pid = self()

      task =
        Task.async(fn ->
          CalcMock
          |> expect(:add, fn _, _ -> :expected end)
          |> stub(:mult, fn _, _ -> :stubbed end)
          |> allow(self(), parent_pid)
        end)

      Task.await(task)

      assert_raise Mox.UnexpectedCallError, fn ->
        CalcMock.add(1, 1)
      end

      CalcMock
      |> expect(:add, 1, fn x, y -> x + y end)

      assert CalcMock.add(1, 1) == 2
    end

    test "raises if you try to allow itself" do
      assert_raise ArgumentError, "owner_pid and allowed_pid must be different", fn ->
        CalcMock
        |> allow(self(), self())
      end
    end

    test "raises if you try to allow already allowed process" do
      {:ok, child_pid} = Task.start_link(fn -> Process.sleep(:infinity) end)

      CalcMock
      |> allow(self(), child_pid)
      |> allow(self(), child_pid)

      Task.async(fn ->
        assert_raise ArgumentError, ~r"it is already allowed by", fn ->
          CalcMock
          |> allow(self(), child_pid)
        end
      end)
      |> Task.await()
    end

    test "raises if you try to allow process with existing expectations set" do
      parent_pid = self()

      {:ok, pid} =
        Task.start_link(fn ->
          CalcMock
          |> expect(:add, fn _, _ -> :expected end)

          send(parent_pid, :ready)
          Process.sleep(:infinity)
        end)

      assert_receive :ready

      assert_raise ArgumentError, ~r"the process has already defined its own expectations", fn ->
        CalcMock
        |> allow(self(), pid)
      end
    end

    test "raises if you try to define expectations on allowed process" do
      parent_pid = self()

      Task.start_link(fn ->
        CalcMock
        |> allow(self(), parent_pid)

        send(parent_pid, :ready)
        Process.sleep(:infinity)
      end)

      assert_receive :ready

      assert_raise ArgumentError, ~r"because the process has been allowed by", fn ->
        CalcMock
        |> expect(:add, fn _, _ -> :expected end)
      end
    end
  end
end
