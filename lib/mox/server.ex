defmodule Mox.Server do
  @moduledoc false

  use GenServer
  @timeout 30000
  @this {:global, __MODULE__}
  @ownership_server {:global, Mox.OwnershipServer}

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

  def allow(mock, owner_pid, pid_or_function) do
    GenServer.call(@this, {:allow, mock, owner_pid, pid_or_function}, @timeout)
  end

  def set_mode(owner_pid, mode) do
    GenServer.call(@this, {:set_mode, owner_pid, mode})
  end

  def ownership_server_child_spec do
    %{id: Mox.OwnershipServer, start: {__MODULE__, :start_ownership_server_link, []}}
  end

  def start_ownership_server_link do
    case NimbleOwnership.start_link(name: @ownership_server) do
      {:error, {:already_started, _}} -> :ignore
      other -> other
    end
  end

  # Callbacks

  def init(:ok) do
    {:ok,
     %{
       expectations: %{},
       deps: %{},
       mode: :private,
       global_owner_pid: nil,
       lazy_calls: false
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
    case NimbleOwnership.fetch_owner(@ownership_server, [owner_pid], mock) do
      {:ok, ^owner_pid} -> :ok
      {:ok, other_owner} -> throw({:reply, {:error, {:currently_allowed, other_owner}}, state})
      :error -> :ok
    end

    reply =
      NimbleOwnership.get_and_update(@ownership_server, owner_pid, mock, fn
        nil ->
          {:ok, %{key => expectation}}

        %{} = expectations ->
          {:ok, Map.update(expectations, key, expectation, &merge_expectation(&1, expectation))}
      end)

    {:reply, reply, state}
  end

  def handle_call(
        {:add_expectation, owner_pid, {mock, _, _} = key, expectation},
        %{mode: :global, global_owner_pid: global_owner_pid} = state
      ) do
    if owner_pid != global_owner_pid do
      {:reply, {:error, {:not_global_owner, global_owner_pid}}, state}
    else
      reply =
        NimbleOwnership.get_and_update(@ownership_server, owner_pid, mock, fn
          nil ->
            {:ok, %{key => expectation}}

          %{} = expectations ->
            {:ok, Map.update(expectations, key, expectation, &merge_expectation(&1, expectation))}
        end)

      {:reply, reply, state}
    end
  end

  def handle_call(
        {:fetch_fun_to_dispatch, caller_pids, {mock, _, _} = key, source},
        %{mode: :private} = state
      ) do
    owner_pid =
      case NimbleOwnership.fetch_owner(@ownership_server, caller_pids, mock) do
        {:ok, owner_pid} -> owner_pid
        :error -> throw({:reply, :no_expectation, state})
      end

    reply =
      NimbleOwnership.get_and_update(@ownership_server, owner_pid, mock, fn expectations ->
        case expectations[key] do
          nil ->
            {:no_expectation, expectations}

          {total, [], nil} ->
            {{:out_of_expectations, total}, expectations}

          {_, [], stub} ->
            {{ok_or_remote(source), stub}, expectations}

          {total, [call | calls], stub} ->
            new_expectations = put_in(expectations[key], {total, calls, stub})
            {{ok_or_remote(source), call}, new_expectations}
        end
      end)

    {:reply, reply, state}
  end

  def handle_call(
        {:fetch_fun_to_dispatch, _caller_pids, {mock, _, _} = key, source},
        %{mode: :global} = state
      ) do
    reply =
      NimbleOwnership.get_and_update(
        @ownership_server,
        state.global_owner_pid,
        mock,
        fn expectations ->
          case expectations[key] do
            nil ->
              {:no_expectation, expectations}

            {total, [], nil} ->
              {{:out_of_expectations, total}, expectations}

            {_, [], stub} ->
              {{ok_or_remote(source), stub}, expectations}

            {total, [call | calls], stub} ->
              new_expectations = put_in(expectations[key], {total, calls, stub})
              {{ok_or_remote(source), call}, new_expectations}
          end
        end
      )

    {:reply, reply, state}
  end

  def handle_call({:verify, owner_pid, mock, test_or_on_exit}, state) do
    expectations = NimbleOwnership.get_owned(@ownership_server, owner_pid, %{})

    pending =
      for {_mock, expected_funs} <- expectations,
          {{module, _, _} = key, {count, [_ | _] = calls, _stub}} <- expected_funs,
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
    if Map.has_key?(state.expectations, pid) do
      {:reply, {:error, :expectations_defined}, state}
    else
      reply =
        case NimbleOwnership.allow(@ownership_server, owner_pid, pid, mock) do
          :ok ->
            :ok

          {:error, %NimbleOwnership.Error{reason: :not_allowed}} ->
            NimbleOwnership.get_and_update(@ownership_server, owner_pid, mock, fn expectations ->
              {:ignored, expectations || %{}}
            end)

            NimbleOwnership.allow(@ownership_server, owner_pid, pid, mock)

          {:error, reason} ->
            {:error, reason}
        end

      {:reply, reply, state}
    end
  end

  def handle_call({:set_mode, owner_pid, :global}, state) do
    state = maybe_add_and_monitor_pid(state, owner_pid)
    {:reply, :ok, %{state | mode: :global, global_owner_pid: owner_pid}}
  end

  def handle_call({:set_mode, _owner_pid, :private}, state) do
    {:reply, :ok, reset_global_mode(state)}
  end

  # Helper functions

  defp reset_global_mode(state) do
    %{state | mode: :private, global_owner_pid: nil}
  end

  defp down(state, pid) do
    {_, state} = pop_in(state.expectations[pid])
    state
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
end
