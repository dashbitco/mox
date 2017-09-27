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
  is to define the mock. To make it available during compilation, create new
  file under `test/support/mocks.ex`:

      Mox.defmock(MyApp.CalcMock, for: MyApp.Calculator)

  The second step is to make sure that files in `test/support` get compiled
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

  Similarly, if you set expectations on the current process and invoke
  the mock on another process, the expectation will not be available.
  In cases where collaboration between multiple processes is required,
  you can skip Mox altogether and directly define a module with the
  behaviour to be tested via multiple processes:

      defmodule MyApp.YetAnotherCalcMock do
        @behaviour MyApp.Calculator
        def add(..., ...), do: ...
        def mult(..., ...), do: ...
      end

  After all, the main motivation behind Mox is to provide concurrent
  mocks defined by explicit contracts. If concurrency is not an option,
  you can still leverage plain Elixir modules to implement those
  contracts.
  """

  @name __MODULE__

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
  `code` will be invoked the `n` times.

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
    validate_mock!(mock)
    arity = :erlang.fun_info(code)[:arity]

    unless function_exported?(mock, name, arity) do
      raise ArgumentError, "unknown function #{name}/#{arity} for mock #{inspect mock}"
    end

    calls = List.duplicate(code, n)
    key = {self(), mock, name, arity}

    case Registry.register(@name, key, {n, calls}) do
      {:ok, _} ->
        mock

      {:error, {:already_registered, pid}} when pid == self() ->
        Registry.update_value(@name, key, fn {current_n, current_calls} ->
          {current_n + n, current_calls ++ calls}
        end)
    end

    mock
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
      for {_, module, name, arity} = key <- Registry.keys(@name, self()),
          module == mock or mock == :all,
          value <- Registry.lookup(@name, key),
          {_pid, {count, calls}} = value,
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
    case Registry.update_value(@name, {self(), mock, name, arity}, &dispatch_update/1) do
      :error ->
        mfa = Exception.format_mfa(mock, name, arity)
        raise UnexpectedCallError, "no expectation defined for #{mfa} in process #{inspect(self())}"

      {_, {count, []}} ->
        mfa = Exception.format_mfa(mock, name, arity)
        raise UnexpectedCallError,
              "expected #{mfa} to be called #{times(count)} but it has been " <>
              "called #{times(count + 1)} in process #{inspect(self())}"

      {_, {_, [call | _]}} ->
        apply(call, args)
    end
  end

  defp times(1), do: "once"
  defp times(n), do: "#{n} times"

  defp dispatch_update({total, []}), do: {total, []}
  defp dispatch_update({total, [_ | tail]}), do: {total, tail}
end
