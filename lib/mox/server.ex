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
    {:ok, %{expectations: %{}, allowances: %{}}}
  end

  def handle_call({:add_expectation, owner_pid, {mock, _, _} = key, expectation}, _from, state) do
    if other_pid = state.allowances[{mock, owner_pid}] do
      {:reply, {:error, {:currently_allowed, other_pid}}, state}
    else
      state = maybe_add_and_monitor_pid(state, owner_pid)

      state =
        update_in state.expectations[owner_pid], fn owned_expectations ->
          Map.update(owned_expectations, key, expectation, &merge_expectation(&1, expectation))
        end

      {:reply, :ok, state}
    end
  end

  def handle_call({:fetch_fun_to_dispatch, caller_pid, {mock, _, _} = key}, _from, state) do
    owner_pid = Map.get(state.allowances, {mock, caller_pid}, caller_pid)

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
    expectations = Map.get(state.expectations, owner_pid, %{})

    pending =
      for {{module, _, _} = key, {count, [_ | _] = calls, _stub}} <- expectations,
          module == mock or mock == :all do
        {key, count, length(calls)}
      end

    {:reply, pending, state}
  end

  def handle_call({:allow, mock, owner_pid, pid}, _from, state) do
    %{allowances: allowances, expectations: expectations} = state
    allowance = allowances[{mock, pid}]

    cond do
      Map.has_key?(expectations, pid) ->
        {:reply, {:error, :expectations_defined}, state}

      allowance && allowance != owner_pid ->
        {:reply, {:error, {:already_allowed, allowance}}, state}

      true ->
        state = put_in(state.allowances[{mock, pid}], owner_pid)
        {:reply, :ok, state}
    end
  end

  def handle_info({:DOWN, _, _, pid, _}, state) do
    {_, state} = pop_in(state.expectations[pid])
    {:noreply, state}
  end

  # Helper functions

  defp maybe_add_and_monitor_pid(state, pid) do
    case state.expectations do
      %{^pid => _} ->
        state

      _ ->
        Process.monitor(pid)
        put_in(state.expectations[pid], %{})
    end
  end

  defp merge_expectation({current_n, current_calls, current_stub}, {n, calls, stub}) do
    {current_n + n, current_calls ++ calls, stub || current_stub}
  end
end
