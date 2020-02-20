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
  is to define the mock with `defmock/2`, usually in your `test_helper.exs`:

      Mox.defmock(MyApp.CalcMock, for: MyApp.Calculator)

  Now in your tests, you can define expectations with `expect/4` and verify
  them via `verify_on_exit!/1`:

      use ExUnit.Case, async: true

      import Mox

      # Make sure mocks are verified when the test exits
      setup :verify_on_exit!

      test "invokes add and mult" do
        MyApp.CalcMock
        |> expect(:add, fn x, y -> x + y end)
        |> expect(:mult, fn x, y -> x * y end)

        assert MyApp.CalcMock.add(2, 3) == 5
        assert MyApp.CalcMock.mult(2, 3) == 6
      end

  In practice, you will have to pass the mock to the system under the test.
  If the system under test relies on application configuration, you should
  also set it before the tests starts to keep the async property. Usually
  in your config files:

      config :my_app, :calculator, MyApp.CalcMock

  Or in your `test_helper.exs`:

      Application.put_env(:my_app, :calculator, MyApp.CalcMock)

  All expectations are defined based on the current process. This
  means multiple tests using the same mock can still run concurrently
  unless the Mox is set to global mode. See the "Multi-process collaboration"
  section.

  Especially if you put the mock into the config/application environment you
  might want the implementation to fall back to the original implementation
  when no expectations are defined. `stub_with/2` is just what you need! Given
  that `MyApp.TestCalculator` is the implementation you are mocking you can
  do the following in your test (for instance inside `setup`):

      Mox.stub_with(MyApp.CalcMock, MyApp.TestCalculator)

  Now, if no expectations are defined it will call the implementation in
  `MyApp.TestCalculator`.

  ## Multiple behaviours

  Mox supports defining mocks for multiple behaviours.

  Suppose your library also defines a scientific calculator behaviour:

      defmodule MyApp.ScientificCalculator do
        @callback exponent(integer(), integer()) :: integer()
      end

  You can mock both the calculator and scientific calculator behaviour:

      Mox.defmock(MyApp.SciCalcMock, for: [MyApp.Calculator, MyApp.ScientificCalculator])

  ## Compile-time requirements

  If the mock needs to be available during the project compilation, for
  instance because you get undefined function warnings, then instead of
  defining the mock in your `test_helper.exs`, you should instead define
  it under `test/support/mocks.ex`:

      Mox.defmock(MyApp.CalcMock, for: MyApp.Calculator)

  Then you need to make sure that files in `test/support` get compiled
  with the rest of the project. Edit your `mix.exs` file to add the
  `test/support` directory to compilation paths:

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

  Mox supports multi-process collaboration via two mechanisms:

    1. explicit allowances
    2. global mode

  The allowance mechanism can still run tests concurrently while
  the global one doesn't. We explore both next.

  ### Explicit allowances

  An allowance permits a child process to use the expectations and stubs
  defined in the parent process while still being safe for async tests.

      test "invokes add and mult from a task" do
        MyApp.CalcMock
        |> expect(:add, fn x, y -> x + y end)
        |> expect(:mult, fn x, y -> x * y end)

        parent_pid = self()

        Task.async(fn ->
          MyApp.CalcMock |> allow(parent_pid, self())
          assert MyApp.CalcMock.add(2, 3) == 5
          assert MyApp.CalcMock.mult(2, 3) == 6
        end)
        |> Task.await
      end

  Note: if you're running on Elixir 1.8.0 or greater and your concurrency comes
  from a `Task` then you don't need to add explicit allowances. Instead
  `$callers` is used to determine the process that actually defined the
  expectations.

  ### Global mode

  Mox supports global mode, where any process can consume mocks and stubs
  defined in your tests. This is enabled automatically based if the test
  is async or not:

      setup :set_mox_from_context
      setup :verify_on_exit!

      test "invokes add and mult from a task" do
        MyApp.CalcMock
        |> expect(:add, fn x, y -> x + y end)
        |> expect(:mult, fn x, y -> x * y end)

        Task.async(fn ->
          assert MyApp.CalcMock.add(2, 3) == 5
          assert MyApp.CalcMock.mult(2, 3) == 6
        end)
        |> Task.await
      end

  ### Blocking on expectations

  If your mock is called in a different process than the test process,
  in some cases there is a chance that the test will finish executing
  before it has a chance to call the mock and meet the expectations.
  Imagine this:

      test "calling a mock from a different process" do
        expect(MyApp.CalcMock, :add, fn x, y -> x + y end)

        spawn(fn -> MyApp.CalcMock.add(4, 2) end)

        verify!()
      end

  The test above has a race condition because there is a chance that the
  `verify!/0` call will happen before the spawned process calls the mock.
  In most cases, you don't control the spawning of the process so you can't
  simply monitor the process to know when it dies in order to avoid this
  race condition. In those cases, the way to go is to "sync up" with the
  process that calls the mock by sending a message to the test process
  from the expectation and using that to know when the expectation has been
  called.

      test "calling a mock from a different process" do
        parent = self()
        ref = make_ref()

        expect(MyApp.CalcMock, :add, fn x, y ->
          send(parent, {ref, :add})
          x + y
        end)

        spawn(fn -> MyApp.CalcMock.add(4, 2) end)

        assert_receive {^ref, :add}

        verify!()
      end

  This way, we'll wait until the expectation is called before calling
  `verify!/0`.
  """

  defmodule UnexpectedCallError do
    defexception [:message]
  end

  defmodule VerificationError do
    defexception [:message]
  end

  @doc """
  Sets the Mox to private mode.

  In private mode, mocks can be set and consumed by the same
  process unless other processes are explicitly allowed.

  ## Examples

      setup :set_mox_private

  """
  def set_mox_private(_context \\ %{}), do: Mox.Server.set_mode(self(), :private)

  @doc """
  Sets the Mox to global mode.

  In global mode, mocks can be consumed by any process.

  An ExUnit case where tests use Mox in global mode cannot be
  `async: true`.

  ## Examples

      setup :set_mox_global
  """
  def set_mox_global(context \\ %{}) do
    if Map.get(context, :async) do
      raise "Mox cannot be set to global mode when the ExUnit case is async. " <>
              "If you want to use Mox in global mode, remove \"async: true\" when using ExUnit.Case"
    else
      Mox.Server.set_mode(self(), :global)
    end
  end

  @doc """
  Chooses the Mox mode based on context.

  When `async: true` is used, `set_mox_private/1` is called,
  otherwise `set_mox_global/1` is used.

  ## Examples

      setup :set_mox_from_context

  """
  def set_mox_from_context(%{async: true} = _context), do: set_mox_private()
  def set_mox_from_context(_context), do: set_mox_global()

  @doc """
  Defines a mock with the given name `:for` the given behaviour(s).

      Mox.defmock(MyMock, for: MyBehaviour)

  With multiple behaviours:

      Mox.defmock(MyMock, for: [MyBehaviour, MyOtherBehaviour])

  ## Skipping optional callbacks

  By default, functions are created for all callbacks, including all optional
  callbacks. But if for some reason you want to skip optional callbacks, you can
  provide the list of callback names to skip (along with their arities) as
  `:skip_optional_callbacks`:

      Mox.defmock(MyMock, for: MyBehaviour, skip_optional_callbacks: [on_success: 2])

  This will define a new mock (`MyMock`) that has a defined function for each
  callback on `MyBehaviour` except for `on_success/2`. Note: you can only skip
  optional callbacks, not required callbacks.

  You can also pass `true` to skip all optional callbacks, or `false` to keep
  the default of generating functions for all optional callbacks.

  ## Passing `@moduledoc`

  You can provide value for `@moduledoc` with `:moduledoc` option.

      Mox.defmock(MyMock, for: MyBehaviour, moduledoc: false)
      Mox.defmock(MyMock, for: MyBehaviour, moduledoc: "My mock module.")

  """
  def defmock(name, options) when is_atom(name) and is_list(options) do
    behaviours =
      case Keyword.fetch(options, :for) do
        {:ok, mocks} -> List.wrap(mocks)
        :error -> raise ArgumentError, ":for option is required on defmock"
      end

    skip_optional_callbacks = Keyword.get(options, :skip_optional_callbacks, [])
    moduledoc = Keyword.get(options, :moduledoc, false)

    doc_header = generate_doc_header(moduledoc)
    compile_header = generate_compile_time_dependency(behaviours)
    callbacks_to_skip = validate_skip_optional_callbacks!(behaviours, skip_optional_callbacks)
    mock_funs = generate_mock_funs(behaviours, callbacks_to_skip)

    define_mock_module(name, behaviours, doc_header ++ compile_header ++ mock_funs)

    name
  end

  defp validate_behaviour!(behaviour) do
    cond do
      Code.ensure_compiled(behaviour) != {:module, behaviour} ->
        raise ArgumentError,
              "module #{inspect(behaviour)} is not available, please pass an existing module to :for"

      not function_exported?(behaviour, :behaviour_info, 1) ->
        raise ArgumentError,
              "module #{inspect(behaviour)} is not a behaviour, please pass a behaviour to :for"

      true ->
        behaviour
    end
  end

  defp generate_doc_header(moduledoc) do
    [
      quote do
        @moduledoc unquote(moduledoc)
      end
    ]
  end

  defp generate_compile_time_dependency(behaviours) do
    for behaviour <- behaviours do
      validate_behaviour!(behaviour)

      quote do
        unquote(behaviour).module_info(:module)
      end
    end
  end

  defp generate_mock_funs(behaviours, callbacks_to_skip) do
    for behaviour <- behaviours,
        {fun, arity} <- behaviour.behaviour_info(:callbacks),
        {fun, arity} not in callbacks_to_skip do
      args = 0..arity |> Enum.to_list() |> tl() |> Enum.map(&Macro.var(:"arg#{&1}", Elixir))

      quote do
        def unquote(fun)(unquote_splicing(args)) do
          Mox.__dispatch__(__MODULE__, unquote(fun), unquote(arity), unquote(args))
        end
      end
    end
  end

  defp validate_skip_optional_callbacks!(behaviours, skip_optional_callbacks) do
    all_optional_callbacks =
      for behaviour <- behaviours,
          {fun, arity} <- behaviour.behaviour_info(:optional_callbacks) do
        {fun, arity}
      end

    case skip_optional_callbacks do
      false ->
        []

      true ->
        all_optional_callbacks

      skip_list when is_list(skip_list) ->
        for callback <- skip_optional_callbacks, callback not in all_optional_callbacks do
          raise ArgumentError,
                "all entries in :skip_optional_callbacks must be an optional callback in one " <>
                  "of the behaviours specified in :for. #{inspect(callback)} was not in the " <>
                  "list of all optional callbacks: #{inspect(all_optional_callbacks)}"
        end

        skip_list

      _ ->
        raise ArgumentError, ":skip_optional_callbacks is required to be a list or boolean"
    end
  end

  defp define_mock_module(name, behaviours, body) do
    info =
      quote do
        def __mock_for__ do
          unquote(behaviours)
        end
      end

    Module.create(name, [info | body], Macro.Env.location(__ENV__))
  end

  @doc """
  Expects the `name` in `mock` with arity given by `code`
  to be invoked `n` times.

  If you're calling your mock from an asynchronous process and want
  to wait for the mock to be called, see the "Blocking on expectations"
  section in the module documentation.

  When `expect/4` is invoked, any previously declared `stub` for the same `name` and arity will
  be removed. This ensures that `expect` will fail if the function is called more than `n` times.
  If a `stub/3` is invoked **after** `expect/4` for the same `name` and arity, the stub will be
  used after all expectations are fulfilled.

  ## Examples

  To expect `MyMock.add/2` to be called once:

      expect(MyMock, :add, fn x, y -> x + y end)

  To expect `MyMock.add/2` to be called five times:

      expect(MyMock, :add, 5, fn x, y -> x + y end)

  To expect `MyMock.add/2` to not be called:

      expect(MyMock, :add, 0, fn x, y -> :ok end)

  `expect/4` can also be invoked multiple times for the same
  name/arity, allowing you to give different behaviours on each
  invocation:

      MyMock
      |> expect(:add, fn x, y -> x + y end)
      |> expect(:add, fn x, y -> x * y end)

  """
  def expect(mock, name, n \\ 1, code)
      when is_atom(mock) and is_atom(name) and is_integer(n) and n >= 0 and is_function(code) do
    calls = List.duplicate(code, n)
    add_expectation!(mock, name, code, {n, calls, nil})
    mock
  end

  @doc """
  Allows the `name` in `mock` with arity given by `code` to
  be invoked zero or many times.

  Unlike expectations, stubs are never verified.

  If expectations and stubs are defined for the same function
  and arity, the stub is invoked only after all expectations are
  fulfilled.

  ## Examples

  To allow `MyMock.add/2` to be called any number of times:

      stub(MyMock, :add, fn x, y -> x + y end)

  `stub/3` will overwrite any previous calls to `stub/3`.
  """
  def stub(mock, name, code)
      when is_atom(mock) and is_atom(name) and is_function(code) do
    add_expectation!(mock, name, code, {0, [], code})
    mock
  end

  @doc """
  Stubs all functions described by the shared behaviours in the `mock` and `module`.

  ## Examples

      defmodule Calculator do
        @callback add(integer(), integer()) :: integer()
        @callback mult(integer(), integer()) :: integer()
      end

      defmodule TestCalculator do
        @behaviour Calculator
        def add(a, b), do: a + b
        def mult(a, b), do: a * b
      end

      defmock(CalcMock, for: Calculator)
      stub_with(CalcMock, TestCalculator)

  This is the same as calling `stub/3` for each behaviour in `CalcMock`:

      stub(CalcMock, :add, &TestCalculator.add/2)
      stub(CalcMock, :mult, &TestCalculator.mult/2)

  """
  def stub_with(mock, module) when is_atom(mock) and is_atom(module) do
    mock_behaviours = mock.__mock_for__()

    behaviours =
      case module_behaviours(module) do
        [] ->
          raise ArgumentError, "#{inspect(module)} does not implement any behaviour"

        behaviours ->
          case Enum.filter(behaviours, &(&1 in mock_behaviours)) do
            [] ->
              raise ArgumentError,
                    "#{inspect(module)} and #{inspect(mock)} do not share any behaviour"

            common ->
              common
          end
      end

    for behaviour <- behaviours,
        {fun, arity} <- behaviour.behaviour_info(:callbacks) do
      stub(mock, fun, :erlang.make_fun(module, fun, arity))
    end

    mock
  end

  defp module_behaviours(module) do
    module.module_info(:attributes)
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
  end

  defp add_expectation!(mock, name, code, value) do
    validate_mock!(mock)
    arity = :erlang.fun_info(code)[:arity]
    key = {mock, name, arity}

    unless function_exported?(mock, name, arity) do
      raise ArgumentError, "unknown function #{name}/#{arity} for mock #{inspect(mock)}"
    end

    case Mox.Server.add_expectation(self(), key, value) do
      :ok ->
        :ok

      {:error, {:currently_allowed, owner_pid}} ->
        inspected = inspect(self())

        raise ArgumentError, """
        cannot add expectations/stubs to #{inspect(mock)} in the current process (#{inspected}) \
        because the process has been allowed by #{inspect(owner_pid)}. \
        You cannot define expectations/stubs in a process that has been allowed
        """

      {:error, {:not_global_owner, global_pid}} ->
        inspected = inspect(self())

        raise ArgumentError, """
        cannot add expectations/stubs to #{inspect(mock)} in the current process (#{inspected}) \
        because Mox is in global mode and the global process is #{inspect(global_pid)}. \
        Only the process that set Mox to global can set expectations/stubs in global mode
        """
    end
  end

  @doc """
  Allows other processes to share expectations and stubs
  defined by owner process.

  ## Examples

  To allow `child_pid` to call any stubs or expectations defined for `MyMock`:

      allow(MyMock, self(), child_pid)

  `allow/3` also accepts named process or via references:

      allow(MyMock, self(), SomeChildProcess)

  """
  def allow(mock, owner_pid, allowed_via) when is_atom(mock) and is_pid(owner_pid) do
    allowed_pid = GenServer.whereis(allowed_via)

    if allowed_pid == owner_pid do
      raise ArgumentError, "owner_pid and allowed_pid must be different"
    end

    case Mox.Server.allow(mock, owner_pid, allowed_pid) do
      :ok ->
        mock

      {:error, {:already_allowed, actual_pid}} ->
        raise ArgumentError, """
        cannot allow #{inspect(allowed_pid)} to use #{inspect(mock)} from #{inspect(owner_pid)} \
        because it is already allowed by #{inspect(actual_pid)}.

        If you are seeing this error message, it is because you are either \
        setting up allowances from different processes or your tests have \
        async: true and you found a race condition where two different tests \
        are allowing the same process
        """

      {:error, :expectations_defined} ->
        raise ArgumentError, """
        cannot allow #{inspect(allowed_pid)} to use #{inspect(mock)} from #{inspect(owner_pid)} \
        because the process has already defined its own expectations/stubs
        """

      {:error, :in_global_mode} ->
        # Already allowed
        mock
    end
  end

  @doc """
  Verifies the current process after it exits.

  If you want to verify expectations for all tests, you can use
  `verify_on_exit!/1` as a setup callback:

      setup :verify_on_exit!

  """
  def verify_on_exit!(_context \\ %{}) do
    pid = self()
    Mox.Server.verify_on_exit(pid)

    ExUnit.Callbacks.on_exit(Mox, fn ->
      verify_mock_or_all!(pid, :all, :on_exit)
    end)
  end

  @doc """
  Verifies that all expectations set by the current process
  have been called.
  """
  def verify! do
    verify_mock_or_all!(self(), :all, :test)
  end

  @doc """
  Verifies that all expectations in `mock` have been called.
  """
  def verify!(mock) do
    validate_mock!(mock)
    verify_mock_or_all!(self(), mock, :test)
  end

  defp verify_mock_or_all!(pid, mock, test_or_on_exit) do
    pending = Mox.Server.verify(pid, mock, test_or_on_exit)

    messages =
      for {{module, name, arity}, total, pending} <- pending do
        mfa = Exception.format_mfa(module, name, arity)
        called = total - pending
        "  * expected #{mfa} to be invoked #{times(total)} but it was invoked #{times(called)}"
      end

    if messages != [] do
      raise VerificationError,
            "error while verifying mocks for #{inspect(pid)}:\n\n" <> Enum.join(messages, "\n")
    end

    :ok
  end

  defp validate_mock!(mock) do
    cond do
      Code.ensure_compiled(mock) != {:module, mock} ->
        raise ArgumentError, "module #{inspect(mock)} is not available"

      not function_exported?(mock, :__mock_for__, 0) ->
        raise ArgumentError, "module #{inspect(mock)} is not a mock"

      true ->
        :ok
    end
  end

  @doc false
  def __dispatch__(mock, name, arity, args) do
    all_callers = [self() | caller_pids()]

    case Mox.Server.fetch_fun_to_dispatch(all_callers, {mock, name, arity}) do
      :no_expectation ->
        mfa = Exception.format_mfa(mock, name, arity)

        raise UnexpectedCallError,
              "no expectation defined for #{mfa} in #{format_process()} with args #{inspect(args)}"

      {:out_of_expectations, count} ->
        mfa = Exception.format_mfa(mock, name, arity)

        raise UnexpectedCallError,
              "expected #{mfa} to be called #{times(count)} but it has been " <>
                "called #{times(count + 1)} in #{format_process()}"

      {:ok, fun_to_call} ->
        apply(fun_to_call, args)
    end
  end

  defp times(1), do: "once"
  defp times(n), do: "#{n} times"

  defp format_process do
    callers = caller_pids()

    "process #{inspect(self())}" <>
      if Enum.empty?(callers) do
        ""
      else
        " (or in its callers #{inspect(callers)})"
      end
  end

  # Find the pid of the actual caller
  defp caller_pids do
    case Process.get(:"$callers") do
      nil -> []
      pids when is_list(pids) -> pids
    end
  end
end
