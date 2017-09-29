defmodule Mox do
  @moduledoc """
  Mox is a library for defining concurrent mocks in Elixir.

  The library follows the principles outlined in
  ["Mocks and explicit contracts"](http://blog.plataformatec.com.br/2015/10/mocks-and-explicit-contracts/),
  summarized below:

    1. No ad-hoc mocks. You can only create mocks based on behaviours

    2. No dynamic generation of modules during tests. Mocks are preferably defined
       in your `test_helper.exs` or in a `setup_all` block and not per test

    3. Concurrency support. Tests using the same mock can still use `async: true`

    4. Rely on pattern matching and function clauses for asserting on the
       input instead of complex expectation rules

  ## Example

  As an example, imagine that your library defines a calculator behaviour:

      defmodule MyApp.Calculator do
        @callback add(integer(), integer()) :: integer()
        @callback mult(integer(), integer()) :: integer()
      end

  If you want to mock the calculator behaviour during tests, the first step
  is to define the mock, usually in your `test_helper.exs`:

      Mox.defmock(MyApp.CalcMock, for: MyApp.Calculator)

  Once the mock is defined, you can pass it to the system under the test.
  If the system under test relies on application configuration, you should
  also set it before the tests starts to keep the async property. Usually
  in your config files:

      config :my_app, :calculator, MyApp.CalcMock

  Or in your `test_helper.exs`:

      Application.put_env(:my_app, :calculator, MyApp.CalcMock)

  Now in your tests, you can define expectations and verify them:

      use ExUnit.Case, async: true

      import Mox

      test "invokes add and mult" do
        MyApp.CalcMock
        |> expect(:add, fn x, y -> x + y end)
        |> expect(:mult, fn x, y -> x * y end)

        assert MyApp.CalcMock.add(2, 3) == 5
        assert MyApp.CalcMock.mult(2, 3) == 6
      after
        verify!() # or verify!(MyApp.CalcMock)
      end

  All expectations are defined based on the current process. This
  means multiple tests using the same mock can still run concurrently.
  It also means verification must be done in the test process itself
  and cannot be done on `on_exit` callbacks.

  ## Compile-time requirements

  If the mock needs to be available during the project compilation, for
  instance because you get undefined function warnings, then instead of
  defining the mock in your `test_helper.exs`, you should instead define
  it under `test/support/mocks.ex`:

      Mox.defmock(MyApp.CalcMock, for: MyApp.Calculator)

  Then you need to make sure that files in `test/support` get compiled
  with the rest of the project. Edit your `mix.exs` file to add `test/support`
  directory to compilation paths:

      def project do
        [
          ...
          elixirc_paths: elixirc_paths(Mix.env),
          ...
        ]
      end

      defp elixirc_paths(:test), do: ["test/support", "lib"]
      defp elixirc_paths(_),     do: ["lib"]

  ## Multi-process collaboration

  Mox currently does not support multi-process collaboration. If you set
  expectations on the current process and invoke the mock on another process,
  the expectation will not be available.

  In cases where collaboration between multiple processes is required, you
  can skip Mox altogether and directly define a module with the behaviour
  to be tested via multiple processes:

      defmodule MyApp.YetAnotherCalcMock do
        @behaviour MyApp.Calculator
        def add(..., ...), do: ...
        def mult(..., ...), do: ...
      end

  After all, the main motivation behind Mox is to provide concurrent mocks
  defined by explicit contracts. If concurrency is not an option, you can still
  leverage plain Elixir modules to implement those contracts.
  """

  defmodule UnexpectedCallError do
    defexception [:message]
  end

  defmodule VerificationError do
    defexception [:message]
  end

  @doc """
  Defines a mock with the given name `:for` the given behaviour.

      Mox.defmock MyMock, for: MyBehaviour

  """
  def defmock(name, options) when is_atom(name) and is_list(options) do
    behaviour = options[:for] || raise ArgumentError, ":for option is required on defmock"
    validate_behaviour!(behaviour)
    define_mock_module(name, behaviour)
    name
  end

  defp validate_behaviour!(behaviour) do
    cond do
      not Code.ensure_loaded?(behaviour) ->
        raise ArgumentError,
              "module #{inspect behaviour} is not available, please pass an existing module to :for"

      not function_exported?(behaviour, :behaviour_info, 1) ->
        raise ArgumentError,
              "module #{inspect behaviour} is not a behaviour, please pass a behaviour to :for"

      true ->
        :ok
    end
  end

  defp define_mock_module(name, behaviour) do
    funs =
      for {fun, arity} <- behaviour.behaviour_info(:callbacks) do
        args = 0..arity |> Enum.to_list |> tl() |> Enum.map(&Macro.var(:"arg#{&1}", Elixir))
        quote do
          def unquote(fun)(unquote_splicing(args)) do
            Mox.__dispatch__(__MODULE__, unquote(fun), unquote(arity), unquote(args))
          end
        end
      end

    info =
      quote do
        def __mock_for__ do
          unquote(behaviour)
        end
      end

    Module.create(name, [info | funs], Macro.Env.location(__ENV__))
  end

  @doc """
  Defines that the `name` in `mock` with arity given by
  `code` will be invoked `n` times.

  ## Examples

  To allow `MyMock.add/2` to be called once:

      expect(MyMock, :add, fn x, y -> x + y end)

  To allow `MyMock.add/2` to be called five times:

      expect(MyMock, :add, 5, fn x, y -> x + y end)

  `expect/4` can also be invoked multiple times for the same
  name/arity, allowing you to give different behaviours on each
  invocation.
  """
  def expect(mock, name, n \\ 1, code)
      when is_atom(mock) and is_atom(name) and is_integer(n) and n >= 1 and is_function(code) do
    key = mock_key!(mock, name, code)
    calls = List.duplicate(code, n)

    Mox.Server.add_expectation(self(), key, {n, calls, nil})

    mock
  end

  @doc """
  Defines that the `name` in `mock` with arity given by
  `code` can be invoked zero or many times.

  Opposite to expectations, stubs are never verified.

  If expectations and stubs are defined for the same function
  and arity, the stub is invoked only after all expecations are
  fulfilled.

  ## Examples

  To allow `MyMock.add/2` to be called any number of times:

      stub(MyMock, :add, fn x, y -> x + y end)

  `stub/3` will overwrite any previous calls to `stub/3`.
  """
  def stub(mock, name, code)
      when is_atom(mock) and is_atom(name) and is_function(code) do
    key = mock_key!(mock, name, code)

    Mox.Server.add_expectation(self(), key, {0, [], code})

    mock
  end

  defp mock_key!(mock, name, code) do
    validate_mock!(mock)
    arity = :erlang.fun_info(code)[:arity]
    unless function_exported?(mock, name, arity) do
      raise ArgumentError, "unknown function #{name}/#{arity} for mock #{inspect mock}"
    end
    {mock, name, arity}
  end

  @doc """
  Verifies that all expectations set by the current process
  have been called.
  """
  def verify! do
    verify_mock_or_all!(:all)
  end

  @doc """
  Verifies that all expectations in `mock` have been called.
  """
  def verify!(mock) do
    validate_mock!(mock)
    verify_mock_or_all!(mock)
  end

  defp verify_mock_or_all!(mock) do
    failed =
      for {module, name, arity} = key <- Mox.Server.keys(self()),
          module == mock or mock == :all,

          {count, calls, _stub} = Mox.Server.get_expectation(self(), key),

          calls != [] do
        mfa = Exception.format_mfa(module, name, arity)
        pending = count - length(calls)
        "  * expected #{mfa} to be invoked #{times(count)} but it was invoked #{times(pending)}"
      end

    if failed != [] do
      raise VerificationError, "error while verifying mocks:\n\n#{Enum.join(failed, "\n")}"
    end

    :ok
  end

  defp validate_mock!(mock) do
    cond do
      not Code.ensure_loaded?(mock) ->
        raise ArgumentError, "module #{inspect mock} is not available"

      not function_exported?(mock, :__mock_for__, 0) ->
        raise ArgumentError, "module #{inspect mock} is not a mock"

      true ->
        :ok
    end
  end

  @doc false
  def __dispatch__(mock, name, arity, args) do
    case Mox.Server.get_fun_to_call(self(), {mock, name, arity}) do
      :no_expectation ->
        mfa = Exception.format_mfa(mock, name, arity)
        raise UnexpectedCallError, "no expectation defined for #{mfa} in process #{inspect(self())}"

      {:out_of_expectations, count} ->
        mfa = Exception.format_mfa(mock, name, arity)
        raise UnexpectedCallError,
              "expected #{mfa} to be called #{times(count)} but it has been " <>
              "called #{times(count + 1)} in process #{inspect(self())}"

      {:ok, fun_to_call} ->
        apply(fun_to_call, args)
    end
  end

  defp times(1), do: "once"
  defp times(n), do: "#{n} times"
end
