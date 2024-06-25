defmodule Mox do
  @moduledoc ~S"""
  Mox is a library for defining concurrent mocks in Elixir.

  The library follows the principles outlined in
  ["Mocks and explicit contracts"](https://dashbit.co/blog/mocks-and-explicit-contracts),
  summarized below:

    1. No ad-hoc mocks. You can only create mocks based on behaviours

    2. No dynamic generation of modules during tests. Mocks are preferably defined
       in your `test_helper.exs` or in a `setup_all` block and not per test

    3. Concurrency support. Tests using the same mock can still use `async: true`

    4. Rely on pattern matching and function clauses for asserting on the
       input instead of complex expectation rules

  ## Example

  Imagine that you have an app that has to display the weather. At first,
  you use an external API to give you the data given a lat/long pair:

      defmodule MyApp.HumanizedWeather do
        def display_temp({lat, long}) do
          {:ok, temp} = MyApp.WeatherAPI.temp({lat, long})
          "Current temperature is #{temp} degrees"
        end

        def display_humidity({lat, long}) do
          {:ok, humidity} = MyApp.WeatherAPI.humidity({lat, long})
          "Current humidity is #{humidity}%"
        end
      end

  However, you want to test the code above without performing external
  API calls. How to do so?

  First, it is important to define the `WeatherAPI` behaviour that we want
  to mock. And we will define a proxy function that will dispatch to
  the desired implementation:

      defmodule MyApp.WeatherAPI do
        @callback temp(MyApp.LatLong.t()) :: {:ok, integer()}
        @callback humidity(MyApp.LatLong.t()) :: {:ok, integer()}

        def temp(lat_long), do: impl().temp(lat_long)
        def humidity(lat_long), do: impl().humidity(lat_long)
        defp impl, do: Application.get_env(:my_app, :weather, MyApp.ExternalWeatherAPI)
      end

  By default, we will dispatch to MyApp.ExternalWeatherAPI, which now contains
  the external API implementation.

  If you want to mock the WeatherAPI behaviour during tests, the first step
  is to define the mock with `defmock/2`, usually in your `test_helper.exs`,
  and configure your application to use it:

      Mox.defmock(MyApp.MockWeatherAPI, for: MyApp.WeatherAPI)
      Application.put_env(:my_app, :weather, MyApp.MockWeatherAPI)

  Now in your tests, you can define expectations with `expect/4` and verify
  them via `verify_on_exit!/1`:

      defmodule MyApp.HumanizedWeatherTest do
        use ExUnit.Case, async: true

        import Mox

        # Make sure mocks are verified when the test exits
        setup :verify_on_exit!

        test "gets and formats temperature and humidity" do
          MyApp.MockWeatherAPI
          |> expect(:temp, fn {_lat, _long} -> {:ok, 30} end)
          |> expect(:humidity, fn {_lat, _long} -> {:ok, 60} end)

          assert MyApp.HumanizedWeather.display_temp({50.06, 19.94}) ==
                   "Current temperature is 30 degrees"

          assert MyApp.HumanizedWeather.display_humidity({50.06, 19.94}) ==
                   "Current humidity is 60%"
        end
      end

  All expectations are defined based on the current process. This
  means multiple tests using the same mock can still run concurrently
  unless the Mox is set to global mode. See the "Multi-process collaboration"
  section.

  One last note, if the mock is used throughout the test suite, you might want
  the implementation to fall back to a stub (or actual) implementation when no
  expectations are defined. You can use `stub_with/2` in a case template that
  is used throughout your test suite:

      defmodule MyApp.Case do
        use ExUnit.CaseTemplate

        setup _ do
          Mox.stub_with(MyApp.MockWeatherAPI, MyApp.StubWeatherAPI)
          :ok
        end
      end

  Now, for every test case that uses `ExUnit.Case`, it can use `MyApp.Case`
  instead. Then, if no expectations are defined it will call the implementation
  in `MyApp.StubWeatherAPI`.

  ## Multiple behaviours

  Mox supports defining mocks for multiple behaviours.

  Suppose your library also defines a behaviour for getting past weather:

      defmodule MyApp.PastWeather do
        @callback past_temp(MyApp.LatLong.t(), DateTime.t()) :: {:ok, integer()}
      end

  You can mock both the weather and past weather behaviour:

      Mox.defmock(MyApp.MockWeatherAPI, for: [MyApp.Weather, MyApp.PastWeather])

  ## Compile-time requirements

  If the mock needs to be available during the project compilation, for
  instance because you get undefined function warnings, then instead of
  defining the mock in your `test_helper.exs`, you should instead define
  it under `test/support/mocks.ex`:

      Mox.defmock(MyApp.MockWeatherAPI, for: MyApp.WeatherAPI)

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
        MyApp.MockWeatherAPI
        |> expect(:temp, fn _loc -> {:ok, 30} end)
        |> expect(:humidity, fn _loc -> {:ok, 60} end)

        parent_pid = self()

        Task.async(fn ->
          MyApp.MockWeatherAPI |> allow(parent_pid, self())

          assert MyApp.HumanizedWeather.display_temp({50.06, 19.94}) ==
                   "Current temperature is 30 degrees"

          assert MyApp.HumanizedWeather.display_humidity({50.06, 19.94}) ==
                   "Current humidity is 60%"
        end)
        |> Task.await
      end

  Note: if you're running on Elixir 1.8.0 or greater and your concurrency comes
  from a `Task` then you don't need to add explicit allowances. Instead
  `$callers` is used to determine the process that actually defined the
  expectations.

  #### Explicit allowances as lazy/deferred functions

  Under some circumstances, the process might not have been already started
  when the allowance happens. In such a case, you might specify the allowance
  as a function in the form `(-> pid())`. This function would be resolved late,
  at the very moment of dispatch. If the function does not return an existing
  PID, Mox will raise a `Mox.UnexpectedCallError` exception.

  ### Global mode

  Mox supports global mode, where any process can consume mocks and stubs
  defined in your tests. `set_mox_from_context/0` automatically calls
  `set_mox_global/1` but only if the test context **doesn't** include
  `async: true`.

  By default the mode is `:private`.

      setup :set_mox_from_context
      setup :verify_on_exit!

      test "invokes add and mult from a task" do
        MyApp.MockWeatherAPI
        |> expect(:temp, fn _loc -> {:ok, 30} end)
        |> expect(:humidity, fn _loc -> {:ok, 60} end)

        Task.async(fn ->
          assert MyApp.HumanizedWeather.display_temp({50.06, 19.94}) ==
                    "Current temperature is 30 degrees"

          assert MyApp.HumanizedWeather.display_humidity({50.06, 19.94}) ==
                    "Current humidity is 60%"
        end)
        |> Task.await
      end

  ### Blocking on expectations

  If your mock is called in a different process than the test process,
  in some cases there is a chance that the test will finish executing
  before it has a chance to call the mock and meet the expectations.
  Imagine this:

      test "calling a mock from a different process" do
        expect(MyApp.MockWeatherAPI, :temp, fn _loc -> {:ok, 30} end)

        spawn(fn -> MyApp.HumanizedWeather.temp({50.06, 19.94}) end)

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

        expect(MyApp.MockWeatherAPI, :temp, fn _loc ->
          send(parent, {ref, :temp})
          {:ok, 30}
        end)

        spawn(fn -> MyApp.HumanizedWeather.temp({50.06, 19.94}) end)

        assert_receive {^ref, :temp}

        verify!()
      end

  This way, we'll wait until the expectation is called before calling
  `verify!/0`.
  """

  @typedoc """
  A mock module.

  This type is available since version 1.1+ of Mox.
  """
  @type t() :: module()

  @timeout 30000
  @this {:global, Mox.Server}

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
  @spec set_mox_private(term()) :: :ok
  def set_mox_private(_context \\ %{}) do
    NimbleOwnership.set_mode_to_private(@this)
  end

  @doc """
  Sets the Mox to global mode.

  In global mode, mocks can be consumed by any process.

  An ExUnit case where tests use Mox in global mode cannot be
  `async: true`.

  ## Examples

      setup :set_mox_global
  """
  @spec set_mox_global(term()) :: :ok
  def set_mox_global(context \\ %{})

  def set_mox_global(%{async: true}) do
    raise "Mox cannot be set to global mode when the ExUnit case is async. " <>
            "If you want to use Mox in global mode, remove \"async: true\" when using ExUnit.Case"
  end

  def set_mox_global(_context) do
    NimbleOwnership.set_mode_to_shared(@this, self())
  end

  @doc """
  Chooses the Mox mode based on context.

  When `async: true` is used, `set_mox_private/1` is called,
  otherwise `set_mox_global/1` is used.

  ## Examples

      setup :set_mox_from_context

  """
  @spec set_mox_from_context(term()) :: :ok
  def set_mox_from_context(%{async: true} = _context), do: set_mox_private()
  def set_mox_from_context(_context), do: set_mox_global()

  @doc """
  Defines a mock with the given name `:for` the given behaviour(s).

      Mox.defmock(MyMock, for: MyBehaviour)

  With multiple behaviours:

      Mox.defmock(MyMock, for: [MyBehaviour, MyOtherBehaviour])

  ## Options

    * `:for` - module or list of modules to define the mock module for.

    * `:moduledoc` - `@moduledoc` for the defined mock module.

    * `:skip_optional_callbacks` - boolean to determine whether to skip
      or generate optional callbacks in the mock module.

  ## Skipping optional callbacks

  By default, functions are created for all the behaviour's callbacks,
  including optional ones. But if for some reason you want to skip one or more
  of its `@optional_callbacks`, you can provide the list of callback names to
  skip (along with their arities) as `:skip_optional_callbacks`:

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
  @spec defmock(mock, [option]) :: mock
        when mock: t(),
             option:
               {:for, module() | [module()]}
               | {:skip_optional_callbacks, boolean()}
               | {:moduledoc, false | String.t()}
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

  defp validate_module!(behaviour) do
    ensure_compiled!(behaviour)
  end

  defp validate_behaviour!(behaviour) do
    if function_exported?(behaviour, :behaviour_info, 1) do
      behaviour
    else
      raise ArgumentError,
            "module #{inspect(behaviour)} is not a behaviour, please pass a behaviour to :for"
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
      behaviour
      |> validate_module!()
      |> validate_behaviour!()

      quote do
        @behaviour unquote(behaviour)
        unquote(behaviour).module_info(:module)
      end
    end
  end

  defp generate_mock_funs(behaviours, callbacks_to_skip) do
    for behaviour <- behaviours,
        {fun, arity} <- behaviour.behaviour_info(:callbacks),
        {fun, arity} not in callbacks_to_skip do
      args = 0..arity |> Enum.drop(1) |> Enum.map(&Macro.var(:"arg#{&1}", Elixir))

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

  To expect `MockWeatherAPI.get_temp/1` to be called once:

      expect(MockWeatherAPI, :get_temp, fn _ -> {:ok, 30} end)

  To expect `MockWeatherAPI.get_temp/1` to be called five times:

      expect(MockWeatherAPI, :get_temp, 5, fn _ -> {:ok, 30} end)

  To expect `MockWeatherAPI.get_temp/1` not to be called (see also `deny/3`):

      expect(MockWeatherAPI, :get_temp, 0, fn _ -> {:ok, 30} end)

  `expect/4` can also be invoked multiple times for the same name/arity,
  allowing you to give different behaviours on each invocation. For instance,
  you could test that your code will try an API call three times before giving
  up:

      MockWeatherAPI
      |> expect(:get_temp, 2, fn _loc -> {:error, :unreachable} end)
      |> expect(:get_temp, 1, fn _loc -> {:ok, 30} end)

      log = capture_log(fn ->
        assert Weather.current_temp(location)
          == "It's currently 30 degrees"
      end)

      assert log =~ "attempt 1 failed"
      assert log =~ "attempt 2 failed"
      assert log =~ "attempt 3 succeeded"

      MockWeatherAPI
      |> expect(:get_temp, 3, fn _loc -> {:error, :unreachable} end)

      assert Weather.current_temp(location) == "Current temperature is unavailable"
  """
  @spec expect(mock, atom(), non_neg_integer(), function()) :: mock when mock: t()
  def expect(mock, name, n \\ 1, code)
      when is_atom(mock) and is_atom(name) and is_integer(n) and n >= 0 and is_function(code) do
    calls = List.duplicate(code, n)
    arity = arity(code)
    add_expectation!(mock, name, arity, {n, calls, nil})
    mock
  end

  @doc """
  Ensures that `name`/`arity` in `mock` is not invoked.

  When `deny/3` is invoked, any previously declared `stub` for the same `name` and arity will
  be removed. This ensures that `deny` will fail if the function is called. If a `stub/3` is
  invoked **after** `deny/3` for the same `name` and `arity`, the stub will be used instead, so
  `deny` will have no effect.

  ## Examples

  To expect `MockWeatherAPI.get_temp/1` to never be called:

      deny(MockWeatherAPI, :get_temp, 1)

  """
  @doc since: "1.2.0"
  @spec deny(mock, atom(), non_neg_integer()) :: mock when mock: t()
  def deny(mock, name, arity)
      when is_atom(mock) and is_atom(name) and is_integer(arity) and arity >= 0 do
    add_expectation!(mock, name, arity, {0, [], nil})
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

  To allow `MockWeatherAPI.get_temp/1` to be called any number of times:

      stub(MockWeatherAPI, :get_temp, fn _loc -> {:ok, 30} end)

  `stub/3` will overwrite any previous calls to `stub/3`.
  """
  @spec stub(mock, atom(), function()) :: mock when mock: t()
  def stub(mock, name, code)
      when is_atom(mock) and is_atom(name) and is_function(code) do
    arity = arity(code)
    add_expectation!(mock, name, arity, {0, [], code})
    mock
  end

  @doc """
  Stubs all functions described by the shared behaviours in the `mock` and `module`.

  ## Examples

      defmodule MyApp.WeatherAPI do
        @callback temp(MyApp.LatLong.t()) :: {:ok, integer()}
        @callback humidity(MyApp.LatLong.t()) :: {:ok, integer()}
      end

      defmodule MyApp.StubWeatherAPI do
        @behaviour MyApp.WeatherAPI
        def temp(_loc), do: {:ok, 30}
        def humidity(_loc), do: {:ok, 60}
      end

      defmock(MyApp.MockWeatherAPI, for: MyApp.WeatherAPI)

      setup do
        stub_with(MyApp.MockWeatherAPI, MyApp.StubWeatherAPI)
        :ok
      end

  This is the same as calling `stub/3` for each callback in `MyApp.MockWeatherAPI`:

      stub(MyApp.MockWeatherAPI, :temp, &MyApp.StubWeatherAPI.temp/1)
      stub(MyApp.MockWeatherAPI, :humidity, &MyApp.StubWeatherAPI.humidity/1)

  """
  @spec stub_with(mock, module()) :: mock when mock: t()
  def stub_with(mock, module) when is_atom(mock) and is_atom(module) do
    behaviours = module_behaviours(module)
    behaviours_mock = mock.__mock_for__()
    behaviours_common = Enum.filter(behaviours, &(&1 in behaviours_mock))

    do_stub_with(mock, module, behaviours, behaviours_common)
  end

  defp do_stub_with(_mock, module, [], _behaviours_common) do
    raise ArgumentError, "#{inspect(module)} does not implement any behaviour"
  end

  defp do_stub_with(mock, module, _behaviours, []) do
    raise ArgumentError,
          "#{inspect(module)} and #{inspect(mock)} do not share any behaviour"
  end

  defp do_stub_with(mock, module, behaviours, _behaviours_common) do
    key_expectation_list =
      for behaviour <- behaviours,
          {fun, arity} <- behaviour.behaviour_info(:callbacks),
          function_exported?(mock, fun, arity) do
        {
          {mock, fun, arity},
          {0, [], :erlang.make_fun(module, fun, arity)}
        }
      end

    add_expectations!(mock, key_expectation_list)

    mock
  end

  defp module_behaviours(module) do
    module.module_info(:attributes)
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
  end

  defp arity(code) do
    {:arity, arity} = :erlang.fun_info(code, :arity)
    arity
  end

  defp add_expectation!(mock, name, arity, value) do
    validate_mock!(mock)
    key = {mock, name, arity}

    unless function_exported?(mock, name, arity) do
      raise ArgumentError, "unknown function #{name}/#{arity} for mock #{inspect(mock)}"
    end

    case add_expectations(self(), mock, [{key, value}]) do
      :ok ->
        :ok

      {:error, error} ->
        raise_cannot_add_expectation!(error, mock)
    end
  end

  defp add_expectations!(mock, key_expectation_list) do
    validate_mock!(mock)

    case add_expectations(self(), mock, key_expectation_list) do
      :ok ->
        :ok

      {:error, error} ->
        raise_cannot_add_expectation!(error, mock)
    end
  end

  defp raise_cannot_add_expectation!(
         %NimbleOwnership.Error{reason: {:already_allowed, owner_pid}},
         mock
       ) do
    inspected = inspect(self())

    raise ArgumentError, """
    cannot add expectations/stubs to #{inspect(mock)} in the current process (#{inspected}) \
    because the process has been allowed by #{inspect(owner_pid)}. \
    You cannot define expectations/stubs in a process that has been allowed
    """
  end

  defp raise_cannot_add_expectation!(
         %NimbleOwnership.Error{reason: {:not_shared_owner, global_pid}},
         mock
       ) do
    inspected = inspect(self())

    raise ArgumentError, """
    cannot add expectations/stubs to #{inspect(mock)} in the current process (#{inspected}) \
    because Mox is in global mode and the global process is #{inspect(global_pid)}. \
    Only the process that set Mox to global can set expectations/stubs in global mode
    """
  end

  defp raise_cannot_add_expectation!(error, _mock) do
    raise error
  end

  @doc """
  Allows other processes to share expectations and stubs
  defined by owner process.

  ## Examples

  To allow `child_pid` to call any stubs or expectations defined for `MyMock`:

      allow(MyMock, self(), child_pid)

  `allow/3` also accepts named process or via references:

      allow(MyMock, self(), SomeChildProcess)

  If the process is not yet started at the moment of allowance definition,
  it might be allowed as a function, assuming at the moment of invocation
  it would have been started. If the function cannot be resolved to a `pid`
  during invocation, the expectation will not succeed.

      allow(MyMock, self(), fn -> GenServer.whereis(Deferred) end)

  """
  @spec allow(mock, pid(), term()) :: mock when mock: t()
  def allow(mock, owner_pid, allowed_via) when is_atom(mock) and is_pid(owner_pid) do
    allowed_pid_or_function =
      case allowed_via do
        fun when is_function(fun, 0) -> fun
        pid_or_name -> GenServer.whereis(pid_or_name)
      end

    if allowed_pid_or_function == owner_pid do
      raise ArgumentError, "owner_pid and allowed_pid must be different"
    end

    case NimbleOwnership.allow(@this, owner_pid, allowed_pid_or_function, mock, @timeout) do
      :ok ->
        mock

      {:error, %NimbleOwnership.Error{reason: :not_allowed}} ->
        # Init the mock and re-allow.
        _ = get_and_update!(owner_pid, mock, &{&1, %{}})
        allow(mock, owner_pid, allowed_via)
        mock

      {:error, %NimbleOwnership.Error{reason: {:already_allowed, actual_pid}}} ->
        raise ArgumentError, """
        cannot allow #{inspect(allowed_pid_or_function)} to use #{inspect(mock)} \
        from #{inspect(owner_pid)} \
        because it is already allowed by #{inspect(actual_pid)}.

        If you are seeing this error message, it is because you are either \
        setting up allowances from different processes or your tests have \
        async: true and you found a race condition where two different tests \
        are allowing the same process
        """

      {:error, %NimbleOwnership.Error{reason: :already_an_owner}} ->
        raise ArgumentError, """
        cannot allow #{inspect(allowed_pid_or_function)} to use \
        #{inspect(mock)} from #{inspect(owner_pid)} \
        because the process has already defined its own expectations/stubs
        """

      {:error, %NimbleOwnership.Error{reason: :cant_allow_in_shared_mode}} ->
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
  @spec verify_on_exit!(term()) :: :ok
  def verify_on_exit!(_context \\ %{}) do
    pid = self()
    NimbleOwnership.set_owner_to_manual_cleanup(@this, pid)

    ExUnit.Callbacks.on_exit(Mox, fn ->
      __verify_mock_or_all__(pid, :all)
      NimbleOwnership.cleanup_owner(@this, pid)
    end)
  end

  @doc """
  Verifies that all expectations set by the current process
  have been called.
  """
  @spec verify!() :: :ok
  def verify! do
    __verify_mock_or_all__(self(), :all)
  end

  @doc """
  Verifies that all expectations in `mock` have been called.
  """
  @spec verify!(t()) :: :ok
  def verify!(mock) do
    validate_mock!(mock)
    __verify_mock_or_all__(self(), mock)
  end

  # Made public for testing.
  @doc false
  def __verify_mock_or_all__(owner_pid, mock_or_all) do
    all_expectations = NimbleOwnership.get_owned(@this, owner_pid, _default = %{}, @timeout)

    pending =
      for {_mock, expected_funs} <- all_expectations,
          {{module, _, _} = key, {count, [_ | _] = calls, _stub}} <- expected_funs,
          module == mock_or_all or mock_or_all == :all do
        {key, count, length(calls)}
      end

    messages =
      for {{module, name, arity}, total, pending} <- pending do
        mfa = Exception.format_mfa(module, name, arity)
        called = total - pending
        "  * expected #{mfa} to be invoked #{times(total)} but it was invoked #{times(called)}"
      end

    if messages != [] do
      raise VerificationError,
            "error while verifying mocks for #{inspect(owner_pid)}:\n\n" <>
              Enum.join(messages, "\n")
    end

    :ok
  end

  defp validate_mock!(mock) do
    ensure_compiled!(mock)

    unless function_exported?(mock, :__mock_for__, 0) do
      raise ArgumentError, "module #{inspect(mock)} is not a mock"
    end

    :ok
  end

  @compile {:no_warn_undefined, {Code, :ensure_compiled!, 1}}

  defp ensure_compiled!(mod) do
    if function_exported?(Code, :ensure_compiled!, 1) do
      Code.ensure_compiled!(mod)
    else
      case Code.ensure_compiled(mod) do
        {:module, mod} ->
          mod

        {:error, reason} ->
          raise ArgumentError,
                "could not load module #{inspect(mod)} due to reason #{inspect(reason)}"
      end
    end
  end

  @doc false
  def __dispatch__(mock, name, arity, args) do
    case fetch_fun_to_dispatch([self() | caller_pids()], {mock, name, arity}) do
      :no_expectation ->
        mfa = Exception.format_mfa(mock, name, arity)

        raise UnexpectedCallError,
              "no expectation defined for #{mfa} in #{format_process()} with args #{inspect(args)}"

      {:out_of_expectations, count} ->
        mfa = Exception.format_mfa(mock, name, arity)

        raise UnexpectedCallError,
              "expected #{mfa} to be called #{times(count)} but it has been " <>
                "called #{times(count + 1)} in #{format_process()}"

      {:remote, fun_to_call} ->
        # It's possible that Mox.Server is running on a remote node in the cluster. Since the
        # function that we passed is not guaranteed to exist on that node (it might have come
        # from a .exs file), find the remote node that hosts Mox.Server, and run the function
        # on that node.
        Mox.Server
        |> :global.whereis_name()
        |> node()
        |> :rpc.call(Kernel, :apply, [fun_to_call, args])

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

  ## Ownership

  @doc false
  def start_link_ownership do
    case NimbleOwnership.start_link(name: @this) do
      {:error, {:already_started, _}} -> :ignore
      other -> other
    end
  end

  defp add_expectations(owner_pid, mock, key_expectation_list) do
    update_fun = &{:ok, init_or_merge_expectations(&1, key_expectation_list)}

    case get_and_update(owner_pid, mock, update_fun) do
      {:ok, _value} ->
        :ok

      {:error, error} ->
        {:error, error}
    end
  end

  defp fetch_fun_to_dispatch(caller_pids, {mock, _, _} = key) do
    parent = self()

    with {:ok, owner_pid} <- fetch_owner_from_callers(caller_pids, mock) do
      get_and_update!(owner_pid, mock, fn expectations ->
        case expectations[key] do
          nil ->
            {:no_expectation, expectations}

          {total, [], nil} ->
            {{:out_of_expectations, total}, expectations}

          {_, [], stub} ->
            {{ok_or_remote(parent), stub}, expectations}

          {total, [call | calls], stub} ->
            new_expectations = put_in(expectations[key], {total, calls, stub})
            {{ok_or_remote(parent), call}, new_expectations}
        end
      end)
    end
  end

  defp fetch_owner_from_callers(caller_pids, mock) do
    # If the mock doesn't have an owner, it can't have expectations so we return :no_expectation.
    case NimbleOwnership.fetch_owner(@this, caller_pids, mock, @timeout) do
      {tag, owner_pid} when tag in [:shared_owner, :ok] -> {:ok, owner_pid}
      :error -> :no_expectation
    end
  end

  defp get_and_update(owner_pid, mock, update_fun) do
    NimbleOwnership.get_and_update(@this, owner_pid, mock, update_fun, @timeout)
  end

  defp get_and_update!(owner_pid, mock, update_fun) do
    case get_and_update(owner_pid, mock, update_fun) do
      {:ok, return} -> return
      {:error, %NimbleOwnership.Error{} = error} -> raise error
    end
  end

  defp init_or_merge_expectations(current_exps, [{key, {n, calls, stub} = new_exp} | tail])
       when is_map(current_exps) or is_nil(current_exps) do
    init_or_merge_expectations(
      Map.update(current_exps || %{}, key, new_exp, fn {current_n, current_calls, _current_stub} ->
        {current_n + n, current_calls ++ calls, stub}
      end),
      tail
    )
  end

  defp init_or_merge_expectations(current_exps, []), do: current_exps

  defp ok_or_remote(source) when node(source) == node(), do: :ok
  defp ok_or_remote(_source), do: :remote
end
