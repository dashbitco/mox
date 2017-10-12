defmodule Mox.Server do
  @moduledoc false

  use GenServer

  # Public API

  def start_link(_options) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def add_expectation(owner_pid, key, value) do
    GenServer.call(__MODULE__, {:add_expectation, owner_pid, key, value})
  end

  def fetch_fun_to_dispatch(caller_pid, key) do
    GenServer.call(__MODULE__, {:fetch_fun_to_dispatch, caller_pid, key})
  end

  def pending_expectations(owner_pid, for) do
    GenServer.call(__MODULE__, {:pending_expectations, owner_pid, for})
  end

  def allow(mock, owner_pid, pid) do
    GenServer.call(__MODULE__, {:allow, mock, owner_pid, pid})
  end

  # Callbacks

  def init(:ok) do
    {:ok, %{expectations: %{}, allowances: %{}, deps: %{}}}
  end

  def handle_call({:add_expectation, owner_pid, {mock, _, _} = key, expectation}, _from, state) do
    if allowance = state.allowances[owner_pid][mock] do
      {:reply, {:error, {:currently_allowed, allowance}}, state}
    else
      state = maybe_add_and_monitor_pid(state, :expectations, owner_pid)

      state =
        update_in state.expectations[owner_pid], fn owned_expectations ->
          Map.update(owned_expectations, key, expectation, &merge_expectation(&1, expectation))
        end

      {:reply, :ok, state}
    end
  end

  def handle_call({:fetch_fun_to_dispatch, caller_pid, {mock, _, _} = key}, _from, state) do
    owner_pid = state.allowances[caller_pid][mock] || caller_pid

    case state.expectations[owner_pid][key] do
      nil ->
        {:reply, :no_expectation, state}

      {total, [], nil} ->
        {:reply, {:out_of_expectations, total}, state}

      {_, [], stub} ->
        {:reply, {:ok, stub}, state}

      {total, [call | calls], stub} ->
        new_state = put_in(state.expectations[owner_pid][key], {total, calls, stub})
        {:reply, {:ok, call}, new_state}
    end
  end

  def handle_call({:pending_expectations, owner_pid, mock}, _from, state) do
    expectations = state.expectations[owner_pid] || %{}

    pending =
      for {{module, _, _} = key, {count, [_ | _] = calls, _stub}} <- expectations,
          module == mock or mock == :all do
        {key, count, length(calls)}
      end

    {:reply, pending, state}
  end

  def handle_call({:allow, mock, owner_pid, pid}, _from, state) do
    %{allowances: allowances, expectations: expectations} = state
    owner_pid = state.allowances[owner_pid][mock] || owner_pid
    allowance = allowances[pid][mock]

    cond do
      Map.has_key?(expectations, pid) ->
        {:reply, {:error, :expectations_defined}, state}

      allowance && allowance != owner_pid ->
        {:reply, {:error, {:already_allowed, allowance}}, state}

      true ->
        state = maybe_add_and_monitor_pid(state, :expectations, owner_pid)
        state = update_in(state.deps[owner_pid], &[{pid, mock} | &1])

        state = maybe_add_and_monitor_pid(state, :allowances, pid)
        state = put_in(state.allowances[pid][mock], owner_pid)

        {:reply, :ok, state}
    end
  end

  def handle_info({:DOWN, _, _, pid, _}, state) do
    {pending, state} = pop_in(state.deps[pid])
    {_, state} = pop_in(state.expectations[pid])
    {_, state} = pop_in(state.allowances[pid])

    state =
      Enum.reduce(pending || [], state, fn {pid, mock}, acc ->
        acc.allowances[pid][mock] |> pop_in() |> elem(1)
      end)

    {:noreply, state}
  end

  # Helper functions

  defp maybe_add_and_monitor_pid(state, key, pid) do
    case state.deps do
      %{^pid => _} ->
        case state do
          %{^key => %{^pid => _}} -> state
          _ -> put_in(state[key][pid], %{})
        end

      _ ->
        Process.monitor(pid)
        state = put_in(state.deps[pid], [])
        state = put_in(state[key][pid], %{})
        state
    end
  end

  defp merge_expectation({current_n, current_calls, current_stub}, {n, calls, stub}) do
    {current_n + n, current_calls ++ calls, stub || current_stub}
  end
end
