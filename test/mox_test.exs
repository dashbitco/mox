defmodule MoxTest do
  use ExUnit.Case, async: true

  import Mox
  doctest Mox

  defmodule Calculator do
    @callback add(integer(), integer()) :: integer()
    @callback mult(integer(), integer()) :: integer()
  end

  defmodule ScientificCalculator do
    @callback exponent(integer(), integer()) :: integer()
  end

  defmock(CalcMock, for: Calculator)
  defmock(SciCalcMock, for: [Calculator, ScientificCalculator])

  def in_all_modes(callback) do
    set_mox_global()
    callback.()
    set_mox_private()
    callback.()
  end

  describe "defmock/2" do
    test "raises for unknown module" do
      assert_raise ArgumentError, ~r"module Unknown is not available", fn ->
        defmock(MyMock, for: Unknown)
      end
    end

    test "raises for non behaviour" do
      assert_raise ArgumentError, ~r"module String is not a behaviour", fn ->
        defmock(MyMock, for: String)
      end
    end

    test "accepts a list of behaviours" do
      assert defmock(MyMock, for: [Calculator, ScientificCalculator])
    end
  end

  describe "expect/4" do
    test "works with multiple behaviours" do
      SciCalcMock
      |> expect(:exponent, fn x, y -> :math.pow(x, y) end)
      |> expect(:add, fn x, y -> x + y end)

      assert SciCalcMock.exponent(2, 3) == 8
      assert SciCalcMock.add(2, 3) == 5
    end

    test "is invoked n times by the same process in private mode" do
      set_mox_private()

      CalcMock
      |> expect(:add, 2, fn x, y -> x + y end)
      |> expect(:mult, fn x, y -> x * y end)
      |> expect(:add, fn _, _ -> 0 end)

      assert CalcMock.add(2, 3) == 5
      assert CalcMock.add(3, 2) == 5
      assert CalcMock.add(:whatever, :whatever) == 0
      assert CalcMock.mult(3, 2) == 6
    end

    test "is invoked n times by any process in global mode" do
      set_mox_global()

      CalcMock
      |> expect(:add, 2, fn x, y -> x + y end)
      |> expect(:mult, fn x, y -> x * y end)
      |> expect(:add, fn _, _ -> 0 end)

      task =
        Task.async(fn ->
          assert CalcMock.add(2, 3) == 5
          assert CalcMock.add(3, 2) == 5
        end)

      Task.await(task)

      assert CalcMock.add(:whatever, :whatever) == 0
      assert CalcMock.mult(3, 2) == 6
    end

    test "can be recharged" do
      expect(CalcMock, :add, fn x, y -> x + y end)
      assert CalcMock.add(2, 3) == 5

      expect(CalcMock, :add, fn x, y -> x + y end)
      assert CalcMock.add(3, 2) == 5
    end

    test "expectations are reclaimed if the global process dies" do
      task =
        Task.async(fn ->
          set_mox_global()

          CalcMock
          |> expect(:add, fn _, _ -> :expected end)
          |> stub(:mult, fn _, _ -> :stubbed end)
        end)

      Task.await(task)

      assert_raise Mox.UnexpectedCallError, fn ->
        CalcMock.add(1, 1)
      end

      CalcMock
      |> expect(:add, 1, fn x, y -> x + y end)

      assert CalcMock.add(1, 1) == 2
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

      msg = ~r"expected CalcMock.add/2 to be called 2 times"

      assert_raise Mox.UnexpectedCallError, msg, fn ->
        CalcMock.add(2, 3) == 5
      end
    end

    test "raises if you try to add expectations from non global process" do
      set_mox_global()

      Task.async(fn ->
        msg =
          ~r"Only the process that set Mox to global can set expectations/stubs in global mode"

        assert_raise ArgumentError, msg, fn ->
          CalcMock
          |> expect(:add, fn _, _ -> :expected end)
        end
      end)
      |> Task.await()
    end
  end

  describe "verify!/0" do
    test "verifies all mocks for the current process in private mode" do
      set_mox_private()

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

    test "verifies all mocks for the current process in global mode" do
      set_mox_global()

      verify!()
      expect(CalcMock, :add, fn x, y -> x + y end)

      message = ~r"expected CalcMock.add/2 to be invoked once but it was invoked 0 times"
      assert_raise Mox.VerificationError, message, &verify!/0

      task =
        Task.async(fn ->
          assert CalcMock.add(2, 3) == 5
        end)

      Task.await(task)

      verify!()
      expect(CalcMock, :add, fn x, y -> x + y end)

      message = ~r"expected CalcMock.add/2 to be invoked 2 times but it was invoked once"
      assert_raise Mox.VerificationError, message, &verify!/0
    end
  end

  describe "verify!/1" do
    test "verifies all mocks for the current process in private mode" do
      set_mox_private()

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

    test "verifies all mocks for current process in global mode" do
      set_mox_global()

      verify!(CalcMock)
      expect(CalcMock, :add, fn x, y -> x + y end)

      message = ~r"expected CalcMock.add/2 to be invoked once but it was invoked 0 times"
      assert_raise Mox.VerificationError, message, &verify!/0

      task =
        Task.async(fn ->
          assert CalcMock.add(2, 3) == 5
        end)

      Task.await(task)

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

    test "verifies all mocks even if none is used in private mode" do
      set_mox_private()
      :ok
    end

    test "verifies all mocks for the current process on exit in private mode" do
      set_mox_private()

      expect(CalcMock, :add, fn x, y -> x + y end)
      assert CalcMock.add(2, 3) == 5
    end

    test "verifies all mocks for the current process on exit with previous verification in private mode" do
      set_mox_private()

      verify!()
      expect(CalcMock, :add, fn x, y -> x + y end)
      assert CalcMock.add(2, 3) == 5
    end

    test "verifies all mocks even if none is used in global mode" do
      set_mox_global()
      :ok
    end

    test "verifies all mocks for current process on exit in global mode" do
      set_mox_global()

      expect(CalcMock, :add, fn x, y -> x + y end)

      task =
        Task.async(fn ->
          assert CalcMock.add(2, 3) == 5
        end)

      Task.await(task)
    end

    test "verifies all mocks for the current process on exit with previous verification in global mode" do
      set_mox_global()

      verify!()
      expect(CalcMock, :add, fn x, y -> x + y end)

      task =
        Task.async(fn ->
          assert CalcMock.add(2, 3) == 5
        end)

      Task.await(task)
    end
  end

  describe "stub/3" do
    test "allows repeated invocations" do
      in_all_modes(fn ->
        stub(CalcMock, :add, fn x, y -> x + y end)
        assert CalcMock.add(1, 2) == 3
        assert CalcMock.add(3, 4) == 7
      end)
    end

    test "does not fail verification if not called" do
      in_all_modes(fn ->
        stub(CalcMock, :add, fn x, y -> x + y end)
        verify!()
      end)
    end

    test "gives expected calls precedence" do
      in_all_modes(fn ->
        CalcMock
        |> stub(:add, fn x, y -> x + y end)
        |> expect(:add, fn _, _ -> :expected end)

        assert CalcMock.add(1, 1) == :expected
        verify!()
      end)
    end

    test "invokes stub after expectations are fulfilled" do
      in_all_modes(fn ->
        CalcMock
        |> stub(:add, fn _x, _y -> :stub end)
        |> expect(:add, 2, fn _, _ -> :expected end)

        assert CalcMock.add(1, 1) == :expected
        assert CalcMock.add(1, 1) == :expected
        assert CalcMock.add(1, 1) == :stub
        verify!()
      end)
    end

    test "overwrites earlier stubs" do
      in_all_modes(fn ->
        CalcMock
        |> stub(:add, fn x, y -> x + y end)
        |> stub(:add, fn _x, _y -> 42 end)

        assert CalcMock.add(1, 1) == 42
      end)
    end

    test "works with multiple behaviours" do
      in_all_modes(fn ->
        SciCalcMock
        |> stub(:add, fn x, y -> x + y end)
        |> stub(:exponent, fn x, y -> :math.pow(x, y) end) 

        assert SciCalcMock.add(1, 1) == 2
        assert SciCalcMock.exponent(2, 3) == 8 
      end)
    end 

    test "raises if a non-mock is given" do
      in_all_modes(fn ->
        assert_raise ArgumentError, ~r"module Unknown is not available", fn ->
          stub(Unknown, :add, fn x, y -> x + y end)
        end

        assert_raise ArgumentError, ~r"module String is not a mock", fn ->
          stub(String, :add, fn x, y -> x + y end)
        end
      end)
    end

    test "raises if function is not in behaviour" do
      in_all_modes(fn ->
        assert_raise ArgumentError, ~r"unknown function oops/2 for mock CalcMock", fn ->
          stub(CalcMock, :oops, fn x, y -> x + y end)
        end

        assert_raise ArgumentError, ~r"unknown function add/3 for mock CalcMock", fn ->
          stub(CalcMock, :add, fn x, y, z -> x + y + z end)
        end
      end)
    end
  end

  describe "stub_with/2" do

    defmodule CalcImplementation do
      @behaviour Calculator
      def add(x, y), do: x + y
      def mult(x, y), do: x * y
    end

    defmodule SciCalcImplementation do
      @behaviour Calculator
      def add(x, y), do: x + y
      def mult(x, y), do: x * y

      @behaviour ScientificCalculator
      def exponent(x, y), do: :math.pow(x, y)
    end

    test "can override stubs" do
      in_all_modes(fn ->
        stub_with(CalcMock, CalcImplementation)
        |> expect(:add, fn 1, 2 -> 4 end)
        assert CalcMock.add(1, 2) == 4
        verify!()
      end)
    end

    test "stubs all functions with functions from a module" do
      in_all_modes(fn ->
        stub_with(CalcMock, CalcImplementation)
        assert CalcMock.add(1, 2) == 3
        assert CalcMock.add(3, 4) == 7
        assert CalcMock.mult(2, 2) == 4
        assert CalcMock.mult(3, 4) == 12
      end)
    end

    test "Leaves behaviours not implemented by the module un-stubbed" do
      in_all_modes(fn ->
        stub_with(SciCalcMock, CalcImplementation)
        assert SciCalcMock.add(1, 2) == 3
        assert SciCalcMock.mult(3, 4) == 12

        assert_raise Mox.UnexpectedCallError, fn ->
          SciCalcMock.exponent(2, 10)
        end
      end)
    end

    test "can stub multiple behaviours from a single module" do
      in_all_modes(fn ->
        stub_with(SciCalcMock, SciCalcImplementation)
        assert SciCalcMock.add(1, 2) == 3
        assert SciCalcMock.mult(3, 4) == 12
        assert SciCalcMock.exponent(2, 10) == 1024
      end)
    end
  end

  describe "allow/3" do
    setup :set_mox_private
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
      end)
      |> Task.await()
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

    test "raises if you try to allow process while in global mode" do
      set_mox_global()
      {:ok, child_pid} = Task.start_link(fn -> Process.sleep(:infinity) end)

      Task.async(fn ->
        assert_raise ArgumentError, ~r"already has access to all defined expectations", fn ->
          CalcMock
          |> allow(self(), child_pid)
        end
      end)
      |> Task.await()
    end
  end
end
