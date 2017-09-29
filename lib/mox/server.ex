defmodule Mox.Server do
  @moduledoc false

  use GenServer

  # Public API

  def start_link(_options) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def add_expectation(owner_pid, key, value) do
    GenServer.call(__MODULE__, {:add_expectation, owner_pid, key, value})
  end

  def fetch_fun_to_dispatch(owner_pid, key) do
    GenServer.call(__MODULE__, {:fetch_fun_to_dispatch, owner_pid, key})
  end

  def pending_expectations(owner_pid, for) do
    GenServer.call(__MODULE__, {:pending_expectations, owner_pid, for})
  end

  # Callbacks

  def handle_call({:add_expectation, owner_pid, key, expectation}, _from, state) do
    state = maybe_add_and_monitor_pid(state, owner_pid)

    state =
      update_in state[owner_pid], fn state ->
        Map.update(state, key, expectation, &merge_expectation(&1, expectation))
      end

    {:reply, :ok, state}
  end

  def handle_call({:get_expectation, owner_pid, key}, _from, state) do
    {:reply, state[owner_pid][key], state}
  end

  def handle_call({:fetch_fun_to_dispatch, owner_pid, key}, _from, state) do
    case state[owner_pid][key] do
      nil ->
        {:reply, :no_expectation, state}

      {total, [], nil} ->
        {:reply, {:out_of_expectations, total}, state}

      {_, [], stub} ->
        {:reply, {:ok, stub}, state}

      {total, [call | calls], stub} ->
        new_state = put_in(state[owner_pid][key], {total, calls, stub})
        {:reply, {:ok, call}, new_state}
    end
  end

  def handle_call({:pending_expectations, owner_pid, mock}, _from, state) do
    expectations = Map.get(state, owner_pid, %{})

    pending =
      for {{module, _, _} = key, {count, [_ | _] = calls, _stub}} <- expectations,
          module == mock or mock == :all do
        {key, count, length(calls)}
      end

    {:reply, pending, state}
  end

  def handle_info({:DOWN, _, _, pid, _}, state) do
    {:noreply, Map.delete(state, pid)}
  end

  # Helper functions

  defp maybe_add_and_monitor_pid(state, pid) do
    case state do
      %{^pid => _} ->
        state

      %{} ->
        Process.monitor(pid)
        Map.put(state, pid, %{})
    end
  end

  defp merge_expectation({current_n, current_calls, current_stub}, {n, calls, stub}) do
    {current_n + n, current_calls ++ calls, stub || current_stub}
  end
end
