defmodule MoxTest do
  use ExUnit.Case, async: true

  import Mox
  doctest Mox

  @compile {:no_warn_undefined,
            [
              MyTrueMock,
              MyFalseMock,
              OneBehaviourMock,
              MyMultiMock,
              MultiBehaviourMock,
              MyScientificMock,
              SciCalcMockWithoutOptional
            ]}

  def in_all_modes(callback) do
    set_mox_global()
    callback.()
    set_mox_private()
    callback.()
  end

  describe "defmock/2" do
    test "raises for unknown module" do
      assert_raise ArgumentError, fn ->
        defmock(MyMock, for: Unknown)
      end
    end

    test "raises for non behaviour" do
      assert_raise ArgumentError, ~r"module String is not a behaviour", fn ->
        defmock(MyMock, for: String)
      end
    end

    test "raises if :for is missing" do
      assert_raise ArgumentError, ":for option is required on defmock", fn ->
        defmock(MyMock, [])
      end
    end

    test "accepts a list of behaviours" do
      assert defmock(MyMock, for: [Calculator, ScientificCalculator])
    end

    test "defines a mock function for all callbacks by default" do
      defmock(MyScientificMock, for: ScientificCalculator)
      all_callbacks = ScientificCalculator.behaviour_info(:callbacks)
      assert all_callbacks -- MyScientificMock.__info__(:functions) == []
    end

    test "accepts a list of callbacks to skip" do
      defmock(MyMultiMock,
        for: [Calculator, ScientificCalculator],
        skip_optional_callbacks: [sin: 1]
      )

      all_callbacks = ScientificCalculator.behaviour_info(:callbacks)
      assert all_callbacks -- MyMultiMock.__info__(:functions) == [sin: 1]
    end

    test "accepts false to indicate all functions should be generated" do
      defmock(MyFalseMock,
        for: [Calculator, ScientificCalculator],
        skip_optional_callbacks: false
      )

      all_callbacks = ScientificCalculator.behaviour_info(:callbacks)
      assert all_callbacks -- MyFalseMock.__info__(:functions) == []
    end

    test "accepts true to indicate no optional functions should be generated" do
      defmock(MyTrueMock, for: [Calculator, ScientificCalculator], skip_optional_callbacks: true)
      all_callbacks = ScientificCalculator.behaviour_info(:callbacks)
      assert all_callbacks -- MyTrueMock.__info__(:functions) == [sin: 1]
    end

    test "raises if :skip_optional_callbacks is not a list or boolean" do
      assert_raise ArgumentError,
                   ":skip_optional_callbacks is required to be a list or boolean",
                   fn ->
                     defmock(MyMock, for: Calculator, skip_optional_callbacks: 42)
                   end
    end

    test "raises if a callback in :skip_optional_callbacks does not exist" do
      expected_error =
        "all entries in :skip_optional_callbacks must be an optional callback in" <>
          " one of the behaviours specified in :for. {:some_other_function, 0} was not in the list" <>
          " of all optional callbacks: []"

      assert_raise ArgumentError, expected_error, fn ->
        defmock(MyMock,
          for: Calculator,
          skip_optional_callbacks: [some_other_function: 0]
        )
      end
    end

    test "raises if a callback in :skip_optional_callbacks is not an optional callback" do
      expected_error =
        "all entries in :skip_optional_callbacks must be an optional callback in" <>
          " one of the behaviours specified in :for. {:exponent, 2} was not in the list" <>
          " of all optional callbacks: [sin: 1]"

      assert_raise ArgumentError, expected_error, fn ->
        defmock(MyMock,
          for: ScientificCalculator,
          skip_optional_callbacks: [exponent: 2]
        )
      end
    end

    @tag :requires_code_fetch_docs
    test "uses false for when moduledoc is not given" do
      assert {:docs_v1, _, :elixir, "text/markdown", :hidden, _, _} =
               Code.fetch_docs(MyMockWithoutModuledoc)
    end

    @tag :requires_code_fetch_docs
    test "passes value to @moduledoc if moduledoc is given" do
      assert {:docs_v1, _, :elixir, "text/markdown", :hidden, _, _} =
               Code.fetch_docs(MyMockWithFalseModuledoc)

      assert {:docs_v1, _, :elixir, "text/markdown", %{"en" => "hello world"}, _, _} =
               Code.fetch_docs(MyMockWithStringModuledoc)
    end

    test "has behaviours of what it mocks" do
      defmock(OneBehaviourMock, for: Calculator)
      assert one_behaviour = OneBehaviourMock.__info__(:attributes)
      assert {:behaviour, [Calculator]} in one_behaviour

      defmock(MultiBehaviourMock, for: [Calculator, ScientificCalculator])
      assert two_behaviour = MultiBehaviourMock.__info__(:attributes)
      assert {:behaviour, [Calculator]} in two_behaviour
      assert {:behaviour, [ScientificCalculator]} in two_behaviour
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

    @tag :requires_caller_tracking
    test "is invoked n times by any process in private mode on Elixir 1.8" do
      set_mox_private()

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

    @tag :requires_caller_tracking
    test "is invoked n times by a sub-process in private mode on Elixir 1.8" do
      set_mox_private()

      CalcMock
      |> expect(:add, 2, fn x, y -> x + y end)
      |> expect(:mult, fn x, y -> x * y end)
      |> expect(:add, fn _, _ -> 0 end)

      task =
        Task.async(fn ->
          assert CalcMock.add(2, 3) == 5
          assert CalcMock.add(3, 2) == 5

          inner_task =
            Task.async(fn ->
              assert CalcMock.add(:whatever, :whatever) == 0
              assert CalcMock.mult(3, 2) == 6
            end)

          Task.await(inner_task)
        end)

      Task.await(task)
    end

    test "allows asserting that function is not called" do
      CalcMock
      |> expect(:add, 0, fn x, y -> x + y end)

      msg = ~r"expected CalcMock.add/2 to be called 0 times but it has been called once"

      assert_raise Mox.UnexpectedCallError, msg, fn ->
        CalcMock.add(2, 3) == 5
      end
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
      assert_raise ArgumentError, ~r"could not load module Unknown", fn ->
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
      assert_raise Mox.UnexpectedCallError,
                   ~r"no expectation defined for CalcMock\.add/2.*with args \[2, 3\]",
                   fn ->
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

    test "raises if all expectations are consumed, even when a stub is defined" do
      stub(CalcMock, :add, fn _, _ -> :stub end)

      expect(CalcMock, :add, 1, fn _, _ -> :expected end)
      assert CalcMock.add(2, 3) == :expected

      assert_raise Mox.UnexpectedCallError, fn ->
        CalcMock.add(2, 3)
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

  describe "deny/3" do
    test "allows asserting that function is not called" do
      deny(CalcMock, :add, 2)

      msg = ~r"expected CalcMock.add/2 to be called 0 times but it has been called once"

      assert_raise Mox.UnexpectedCallError, msg, fn ->
        CalcMock.add(2, 3) == 5
      end
    end

    test "raises if a non-mock is given" do
      assert_raise ArgumentError, ~r"could not load module Unknown", fn ->
        deny(Unknown, :add, 2)
      end

      assert_raise ArgumentError, ~r"module String is not a mock", fn ->
        deny(String, :add, 2)
      end
    end

    test "raises if function is not in behaviour" do
      assert_raise ArgumentError, ~r"unknown function oops/2 for mock CalcMock", fn ->
        deny(CalcMock, :oops, 2)
      end

      assert_raise ArgumentError, ~r"unknown function add/3 for mock CalcMock", fn ->
        deny(CalcMock, :add, 3)
      end
    end

    test "raises even when a stub is defined" do
      stub(CalcMock, :add, fn _, _ -> :stub end)
      deny(CalcMock, :add, 2)

      assert_raise Mox.UnexpectedCallError, fn ->
        CalcMock.add(2, 3)
      end
    end

    test "raises if you try to add expectations from non global process" do
      set_mox_global()

      Task.async(fn ->
        msg =
          ~r"Only the process that set Mox to global can set expectations/stubs in global mode"

        assert_raise ArgumentError, msg, fn ->
          deny(CalcMock, :add, 2)
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
      expect(SciCalcOnlyMock, :exponent, fn x, y -> x * y end)

      error = assert_raise(Mox.VerificationError, &verify!/0)

      assert error.message =~
               ~r"expected CalcMock.add/2 to be invoked once but it was invoked 0 times"

      assert error.message =~
               ~r"expected SciCalcOnlyMock.exponent/2 to be invoked once but it was invoked 0 times"

      CalcMock.add(2, 3)
      error = assert_raise(Mox.VerificationError, &verify!/0)
      refute error.message =~ ~r"expected CalcMock.add/2"

      assert error.message =~
               ~r"expected SciCalcOnlyMock.exponent/2 to be invoked once but it was invoked 0 times"

      SciCalcOnlyMock.exponent(2, 3)
      verify!()

      # Adding another expected call makes verification fail again
      expect(CalcMock, :add, fn x, y -> x + y end)
      error = assert_raise(Mox.VerificationError, &verify!/0)

      assert error.message =~
               ~r"expected CalcMock.add/2 to be invoked 2 times but it was invoked once"

      refute error.message =~ ~r"expected SciCalcOnlyMock.exponent/2"
    end

    test "verifies all mocks for the current process in global mode" do
      set_mox_global()

      verify!()
      expect(CalcMock, :add, fn x, y -> x + y end)
      expect(SciCalcOnlyMock, :exponent, fn x, y -> x * y end)

      error = assert_raise(Mox.VerificationError, &verify!/0)

      assert error.message =~
               ~r"expected CalcMock.add/2 to be invoked once but it was invoked 0 times"

      assert error.message =~
               ~r"expected SciCalcOnlyMock.exponent/2 to be invoked once but it was invoked 0 times"

      Task.async(fn -> SciCalcOnlyMock.exponent(2, 4) end)
      |> Task.await()

      error = assert_raise(Mox.VerificationError, &verify!/0)

      assert error.message =~
               ~r"expected CalcMock.add/2 to be invoked once but it was invoked 0 times"

      refute error.message =~ ~r"expected SciCalcOnlyMock.exponent/2"

      Task.async(fn -> CalcMock.add(5, 6) end)
      |> Task.await()

      verify!()

      expect(CalcMock, :add, fn x, y -> x + y end)
      error = assert_raise(Mox.VerificationError, &verify!/0)

      assert error.message =~
               ~r"expected CalcMock.add/2 to be invoked 2 times but it was invoked once"

      refute error.message =~ ~r"expected SciCalcOnlyMock.exponent/2"
    end
  end

  describe "verify!/1" do
    test "verifies all mocks for the current process in private mode" do
      set_mox_private()

      verify!(CalcMock)
      verify!(SciCalcOnlyMock)
      expect(CalcMock, :add, fn x, y -> x + y end)
      expect(SciCalcOnlyMock, :exponent, fn x, y -> x * y end)

      error = assert_raise(Mox.VerificationError, fn -> verify!(CalcMock) end)

      assert error.message =~
               ~r"expected CalcMock.add/2 to be invoked once but it was invoked 0 times"

      refute error.message =~ ~r"expected SciCalcOnlyMock.exponent/2"

      error = assert_raise(Mox.VerificationError, fn -> verify!(SciCalcOnlyMock) end)

      assert error.message =~
               ~r"expected SciCalcOnlyMock.exponent/2 to be invoked once but it was invoked 0 times"

      refute error.message =~ ~r"expected CalcMock.add/2"

      CalcMock.add(2, 3)
      verify!(CalcMock)

      error = assert_raise(Mox.VerificationError, fn -> verify!(SciCalcOnlyMock) end)

      assert error.message =~
               ~r"expected SciCalcOnlyMock.exponent/2 to be invoked once but it was invoked 0 times"

      refute error.message =~ ~r"expected CalcMock.add/2"

      SciCalcOnlyMock.exponent(2, 3)
      verify!(CalcMock)
      verify!(SciCalcOnlyMock)

      expect(CalcMock, :add, fn x, y -> x + y end)
      error = assert_raise Mox.VerificationError, fn -> verify!(CalcMock) end

      assert error.message =~
               ~r"expected CalcMock.add/2 to be invoked 2 times but it was invoked once"

      refute error.message =~ ~r"expected SciCalcOnlyMock.exponent/2"
      verify!(SciCalcOnlyMock)
    end

    test "verifies all mocks for current process in global mode" do
      set_mox_global()

      verify!(CalcMock)
      verify!(SciCalcOnlyMock)
      expect(CalcMock, :add, fn x, y -> x + y end)
      expect(SciCalcOnlyMock, :exponent, fn x, y -> x * y end)

      error = assert_raise(Mox.VerificationError, fn -> verify!(CalcMock) end)

      assert error.message =~
               ~r"expected CalcMock.add/2 to be invoked once but it was invoked 0 times"

      refute error.message =~ ~r"expected SciCalcOnlyMock.exponent/2"

      error = assert_raise(Mox.VerificationError, fn -> verify!(SciCalcOnlyMock) end)

      assert error.message =~
               ~r"expected SciCalcOnlyMock.exponent/2 to be invoked once but it was invoked 0 times"

      refute error.message =~ ~r"expected CalcMock.add/2"

      Task.async(fn -> CalcMock.add(2, 3) end)
      |> Task.await()

      verify!(CalcMock)

      error = assert_raise(Mox.VerificationError, fn -> verify!(SciCalcOnlyMock) end)

      assert error.message =~
               ~r"expected SciCalcOnlyMock.exponent/2 to be invoked once but it was invoked 0 times"

      refute error.message =~ ~r"expected CalcMock.add/2"

      SciCalcOnlyMock.exponent(2, 3)
      verify!(CalcMock)
      verify!(SciCalcOnlyMock)

      expect(CalcMock, :add, fn x, y -> x + y end)

      error = assert_raise(Mox.VerificationError, &verify!/0)

      assert error.message =~
               ~r"expected CalcMock.add/2 to be invoked 2 times but it was invoked once"

      refute error.message =~ ~r"expected SciCalcOnlyMock.exponent/2"

      verify!(SciCalcOnlyMock)
    end

    test "raises if a non-mock is given" do
      assert_raise ArgumentError, ~r"could not load module Unknown", fn ->
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

    test "raises if the mocks are not called" do
      pid = self()

      verify_on_exit!()

      # This replicates exactly what verify_on_exit/1 does, but it adds an assertion
      # in there. There's no easy way to test that something gets raised in an on_exit
      # callback.
      ExUnit.Callbacks.on_exit(Mox, fn ->
        assert_raise Mox.VerificationError, fn ->
          Mox.__verify_mock_or_all__(pid, :all)
          NimbleOwnership.cleanup_owner({:global, Mox.Server}, pid)
        end
      end)

      set_mox_private()

      expect(CalcMock, :add, fn x, y -> x + y end)
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

    test "a stub declared after an expect is invoked after all expectations are fulfilled" do
      in_all_modes(fn ->
        CalcMock
        |> expect(:add, 2, fn _, _ -> :expected end)
        |> stub(:add, fn _x, _y -> :stub end)

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
        assert_raise ArgumentError, ~r"could not load module Unknown", fn ->
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

    defmodule SciCalcFullImplementation do
      @behaviour Calculator
      def add(x, y), do: x + y
      def mult(x, y), do: x * y

      @behaviour ScientificCalculator
      def exponent(x, y), do: :math.pow(x, y)
      def sin(x), do: :math.sin(x)
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

    test "stubs functions which are optional callbacks" do
      in_all_modes(fn ->
        stub_with(SciCalcMock, SciCalcFullImplementation)
        assert SciCalcMock.add(1, 2) == 3
        assert SciCalcMock.mult(3, 4) == 12
        assert SciCalcMock.exponent(2, 10) == 1024
        assert SciCalcMock.sin(0) == 0.0
      end)
    end

    test "skips undefined functions which are optional callbacks" do
      in_all_modes(fn ->
        stub_with(SciCalcMockWithoutOptional, SciCalcImplementation)
        assert SciCalcMockWithoutOptional.add(1, 2) == 3
        assert SciCalcMockWithoutOptional.mult(3, 4) == 12
        assert SciCalcMockWithoutOptional.exponent(2, 10) == 1024

        assert_raise UndefinedFunctionError, fn ->
          SciCalcMockWithoutOptional.sin(1)
        end
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

    test "does not crash verify when all callbacks are optional and skipped" do
      defmodule AllOptionalImpl do
        @behaviour AllOptionalCallbacks
        def optional_fun, do: :ok
      end

      in_all_modes(fn ->
        stub_with(AllOptionalMock, AllOptionalImpl)
        verify!()
      end)
    end
  end

  describe "allow/3" do
    setup :set_mox_private
    setup :verify_on_exit!

    test "allows different processes to share mocks from parent process" do
      parent_pid = self()

      {:ok, child_pid} =
        start_link_no_callers(fn ->
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

      async_no_callers(fn ->
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
        start_link_no_callers(fn ->
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

      {_pid, ref} =
        spawn_monitor(fn ->
          CalcMock
          |> expect(:add, fn _, _ -> :expected end)
          |> stub(:mult, fn _, _ -> :stubbed end)
          |> allow(self(), parent_pid)
        end)

      receive do
        {:DOWN, ^ref, _, _, _} -> :ok
      end

      assert_raise Mox.UnexpectedCallError, fn ->
        CalcMock.add(1, 1)
      end

      CalcMock
      |> expect(:add, 1, fn x, y -> x + y end)

      assert CalcMock.add(1, 1) == 2
    end

    test "allowances support locally registered processes" do
      parent_pid = self()
      process_name = :test_process

      {:ok, child_pid} =
        Task.start_link(fn ->
          receive do
            :call_mock ->
              add_result = CalcMock.add(1, 1)
              send(parent_pid, {:verify, add_result})
          end
        end)

      Process.register(child_pid, process_name)

      CalcMock
      |> expect(:add, fn _, _ -> :expected end)
      |> allow(self(), process_name)

      send(:test_process, :call_mock)

      assert_receive {:verify, add_result}
      assert add_result == :expected
    end

    test "allowances support processes registered through a Registry" do
      defmodule CalculatorServer do
        use GenServer

        def init(args) do
          {:ok, args}
        end

        def handle_call(:call_mock, _from, []) do
          add_result = CalcMock.add(1, 1)
          {:reply, add_result, []}
        end
      end

      {:ok, _} = Registry.start_link(keys: :unique, name: Registry.Test)
      name = {:via, Registry, {Registry.Test, :test_process}}
      {:ok, _} = GenServer.start_link(CalculatorServer, [], name: name)

      CalcMock
      |> expect(:add, fn _, _ -> :expected end)
      |> allow(self(), name)

      add_result = GenServer.call(name, :call_mock)
      assert add_result == :expected
    end

    test "allowances support lazy calls for processes registered through a Registry" do
      defmodule CalculatorServer_Lazy do
        use GenServer

        def init(args) do
          {:ok, args}
        end

        def handle_call(:call_mock, _from, []) do
          add_result = CalcMock.add(1, 1)
          {:reply, add_result, []}
        end
      end

      {:ok, _} = Registry.start_link(keys: :unique, name: Registry.Test)
      name = {:via, Registry, {Registry.Test, :test_process_lazy}}

      CalcMock
      |> expect(:add, fn _, _ -> :expected end)
      |> allow(self(), fn -> GenServer.whereis(name) end)

      {:ok, _} = GenServer.start_link(CalculatorServer_Lazy, [], name: name)
      add_result = GenServer.call(name, :call_mock)
      assert add_result == :expected
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

    test "is ignored if you allow process while in global mode" do
      set_mox_global()
      {:ok, child_pid} = Task.start_link(fn -> Process.sleep(:infinity) end)

      Task.async(fn ->
        mock = CalcMock
        assert allow(mock, self(), child_pid) == mock
      end)
      |> Task.await()
    end
  end

  describe "set_mox_global/1" do
    test "raises if the test case is async" do
      message = ~r/Mox cannot be set to global mode when the ExUnit case is async/
      assert_raise RuntimeError, message, fn -> set_mox_global(%{async: true}) end
    end
  end

  defp async_no_callers(fun) do
    Task.async(fn ->
      Process.delete(:"$callers")
      fun.()
    end)
  end

  defp start_link_no_callers(fun) do
    Task.start_link(fn ->
      Process.delete(:"$callers")
      fun.()
    end)
  end
end
