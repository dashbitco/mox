defmodule Mox.Server do
  @moduledoc false

  use GenServer
  @timeout 30000
  @this {:global, __MODULE__}

  # API

  def start_link(_options) do
    case GenServer.start_link(__MODULE__, :ok, name: @this) do
      {:error, {:already_started, _}} ->
        :ignore

      other ->
        other
    end
  end

  def add_expectation(owner_pid, key, value) do
    GenServer.call(@this, {:add_expectation, owner_pid, key, value}, @timeout)
  end

  def fetch_fun_to_dispatch(caller_pids, key) do
    GenServer.call(@this, {:fetch_fun_to_dispatch, caller_pids, key, self()}, @timeout)
  end

  def verify(owner_pid, for, test_or_on_exit) do
    GenServer.call(@this, {:verify, owner_pid, for, test_or_on_exit}, @timeout)
  end

  def verify_on_exit(pid) do
    GenServer.call(@this, {:verify_on_exit, pid}, @timeout)
  end

  def allow(mock, owner_pid, pid_or_promise) do
    GenServer.call(@this, {:allow, mock, owner_pid, pid_or_promise}, @timeout)
  end

  def set_mode(owner_pid, mode) do
    GenServer.call(@this, {:set_mode, owner_pid, mode})
  end

  # Callbacks

  def init(:ok) do
    {:ok,
     %{
       expectations: %{},
       allowances: %{},
       deps: %{},
       mode: :private,
       global_owner_pid: nil,
       promises: false
     }}
  end

  def handle_call(msg, _from, state) do
    # The global process may have terminated and we did not receive
    # the DOWN message yet, so we always check accordingly if it is alive.
    with %{mode: :global, global_owner_pid: global_owner_pid} <- state,
         false <- Process.alive?(global_owner_pid) do
      handle_call(msg, reset_global_mode(state))
    else
      _ -> handle_call(msg, state)
    end
  end

  def handle_info({:DOWN, _, _, pid, _}, state) do
    state =
      case state.global_owner_pid do
        ^pid -> reset_global_mode(state)
        _ -> state
      end

    state =
      case state.deps do
        %{^pid => {:DOWN, _}} -> down(state, pid)
        %{} -> state
      end

    {:noreply, state}
  end

  # handle_call

  def handle_call(
        {:add_expectation, owner_pid, {mock, _, _} = key, expectation},
        %{mode: :private} = state
      ) do
    if allowance = state.allowances[owner_pid][mock] do
      {:reply, {:error, {:currently_allowed, allowance}}, state}
    else
      state = maybe_add_and_monitor_pid(state, owner_pid)

      state =
        update_in(state, [:expectations, pid_map(owner_pid)], fn owned_expectations ->
          Map.update(owned_expectations, key, expectation, &merge_expectation(&1, expectation))
        end)

      {:reply, :ok, state}
    end
  end

  def handle_call(
        {:add_expectation, owner_pid, {_mock, _, _} = key, expectation},
        %{mode: :global, global_owner_pid: global_owner_pid} = state
      ) do
    if owner_pid != global_owner_pid do
      {:reply, {:error, {:not_global_owner, global_owner_pid}}, state}
    else
      state =
        update_in(state, [:expectations, pid_map(owner_pid)], fn owned_expectations ->
          Map.update(owned_expectations, key, expectation, &merge_expectation(&1, expectation))
        end)

      {:reply, :ok, state}
    end
  end

  def handle_call(
        {:fetch_fun_to_dispatch, caller_pids, {mock, _, _} = key, source},
        %{mode: :private, promises: promises} = state
      ) do
    state = maybe_revalidate_promises(promises, state)

    owner_pid =
      Enum.find_value(caller_pids, List.first(caller_pids), fn caller_pid ->
        cond do
          state.allowances[caller_pid][mock] -> state.allowances[caller_pid][mock]
          state.expectations[caller_pid][key] -> caller_pid
          true -> false
        end
      end)

    case state.expectations[owner_pid][key] do
      nil ->
        {:reply, :no_expectation, state}

      {total, [], nil} ->
        {:reply, {:out_of_expectations, total}, state}

      {_, [], stub} ->
        {:reply, {ok_or_remote(source), stub}, state}

      {total, [call | calls], stub} ->
        new_state = put_in(state.expectations[owner_pid][key], {total, calls, stub})
        {:reply, {ok_or_remote(source), call}, new_state}
    end
  end

  def handle_call(
        {:fetch_fun_to_dispatch, _caller_pids, {_mock, _, _} = key, source},
        %{mode: :global} = state
      ) do
    case state.expectations[state.global_owner_pid][key] do
      nil ->
        {:reply, :no_expectation, state}

      {total, [], nil} ->
        {:reply, {:out_of_expectations, total}, state}

      {_, [], stub} ->
        {:reply, {ok_or_remote(source), stub}, state}

      {total, [call | calls], stub} ->
        new_state = put_in(state.expectations[state.global_owner_pid][key], {total, calls, stub})
        {:reply, {ok_or_remote(source), call}, new_state}
    end
  end

  def handle_call({:verify, owner_pid, mock, test_or_on_exit}, state) do
    expectations = state.expectations[owner_pid] || %{}

    pending =
      for {{module, _, _} = key, {count, [_ | _] = calls, _stub}} <- expectations,
          module == mock or mock == :all do
        {key, count, length(calls)}
      end

    state =
      if test_or_on_exit == :on_exit do
        down(state, owner_pid)
      else
        state
      end

    {:reply, pending, state}
  end

  def handle_call({:verify_on_exit, pid}, state) do
    state = maybe_add_and_monitor_pid(state, pid, :on_exit, fn {_, deps} -> {:on_exit, deps} end)
    {:reply, :ok, state}
  end

  def handle_call({:allow, _, _, _}, %{mode: :global} = state) do
    {:reply, {:error, :in_global_mode}, state}
  end

  def handle_call({:allow, mock, owner_pid, pid}, %{mode: :private} = state) do
    %{allowances: allowances, expectations: expectations} = state
    owner_pid = state.allowances[owner_pid][mock] || owner_pid
    allowance = allowances[pid][mock]

    cond do
      Map.has_key?(expectations, pid) ->
        {:reply, {:error, :expectations_defined}, state}

      allowance && allowance != owner_pid ->
        {:reply, {:error, {:already_allowed, allowance}}, state}

      true ->
        state =
          maybe_add_and_monitor_pid(state, owner_pid, :DOWN, fn {on, deps} ->
            {on, [{pid, mock} | deps]}
          end)

        state =
          state
          |> put_in([:allowances, pid_map(pid), mock], owner_pid)
          |> update_in([:promises], &(&1 or match?(fun when is_function(fun, 0), pid)))

        {:reply, :ok, state}
    end
  end

  def handle_call({:set_mode, owner_pid, :global}, state) do
    state = maybe_add_and_monitor_pid(state, owner_pid)
    {:reply, :ok, %{state | mode: :global, global_owner_pid: owner_pid}}
  end

  def handle_call({:set_mode, _owner_pid, :private}, state) do
    {:reply, :ok, %{state | mode: :private, global_owner_pid: nil}}
  end

  # Helper functions

  defp reset_global_mode(state) do
    %{state | mode: :private, global_owner_pid: nil}
  end

  defp down(state, pid) do
    {{_, deps}, state} = pop_in(state.deps[pid])
    {_, state} = pop_in(state.expectations[pid])
    {_, state} = pop_in(state.allowances[pid])

    Enum.reduce(deps, state, fn {pid, mock}, acc ->
      acc.allowances[pid][mock] |> pop_in() |> elem(1)
    end)
  end

  defp pid_map(pid) do
    Access.key(pid, %{})
  end

  defp maybe_add_and_monitor_pid(state, pid) do
    maybe_add_and_monitor_pid(state, pid, :DOWN, & &1)
  end

  defp maybe_add_and_monitor_pid(state, pid, on, fun) do
    case state.deps do
      %{^pid => entry} ->
        put_in(state.deps[pid], fun.(entry))

      _ ->
        Process.monitor(pid)
        state = put_in(state.deps[pid], {on, []})
        state
    end
  end

  defp merge_expectation({current_n, current_calls, _current_stub}, {n, calls, stub}) do
    {current_n + n, current_calls ++ calls, stub}
  end

  defp ok_or_remote(source) when node(source) == node(), do: :ok
  defp ok_or_remote(_source), do: :remote

  defp maybe_revalidate_promises(false, state), do: state

  defp maybe_revalidate_promises(true, state) do
    state.allowances
    |> Enum.reduce({[], [], false}, fn
      {key, value}, {result, resolved, unresolved} when is_function(key, 0) ->
        case key.() do
          pid when is_pid(pid) ->
            {[{pid, value} | result], [{key, pid} | resolved], unresolved}

          _ ->
            {[{key, value} | result], resolved, true}
        end

      kv, {result, resolved, unresolved} ->
        {[kv | result], resolved, unresolved}
    end)
    |> fix_resolved(state)
  end

  defp fix_resolved({_, [], _}, state), do: state

  defp fix_resolved({allowances, fun_to_pids, promises}, state) do
    fun_to_pids = Map.new(fun_to_pids)

    deps =
      Map.new(state.deps, fn {pid, {fun, deps}} ->
        deps =
          Enum.map(deps, fn
            {fun, mock} when is_function(fun, 0) -> {Map.get(fun_to_pids, fun, fun), mock}
            other -> other
          end)

        {pid, {fun, deps}}
      end)

    %{state | deps: deps, allowances: Map.new(allowances), promises: promises}
  end
end
